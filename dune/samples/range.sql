/* get rebalance tx hash*/
WITH rebalancetxs AS(
    SELECT evt_tx_hash
    FROM orange_finance_arbitrum.OrangeAlphaVault_evt_Action
    WHERE actionType = 3
),

/*  
    two mint events in one tx
    time, lowerTick, upperTick, range <- band order
    time, lowerTick, upperTick, range <- limit order
*/
mint AS(
 SELECT
  position.tickLower AS lowerTick,   
  position.tickUpper AS UpperTick,  
  ABS(position.tickLower - position.tickUpper) AS range,
  evt_block_time AS Time 
 FROM (
 select evt_block_time, evt_tx_hash, tickLower, tickUpper from uniswap_v3_arbitrum.Pair_evt_Mint
 UNION
 select evt_block_time, evt_tx_hash, tickLower, tickUpper from uniswap_v3_arbitrum.Pair_evt_Collect
 UNION
 select evt_block_time, evt_tx_hash, tickLower, tickUpper from uniswap_v3_arbitrum.Pair_evt_Burn
 ) AS position, rebalancetxs
 WHERE position.evt_tx_hash IN (rebalancetxs.evt_tx_hash)
),

/*
    wide range -> baseOrder
    time, baseLower, baseLower, limitLower, limitUpper
*/
range AS(
    SELECT 
        m1.Time,
        m1.lowerTick AS baseLower,
        m1.upperTick AS baseUpper,
        m2.lowerTick AS limitLower,
        m2.upperTick AS limitUpper
    FROM mint as m1 
    LEFT JOIN mint M2 ON date_trunc('minute', M1.Time) = date_trunc('minute', M2.Time) AND M1.range > M2.range
),

/*
    tick to price
*/
rangePrice AS(
    SELECT 
        range.time AS Time,
        POW(10,12)*POW(1.0001,range.baseLower)*priceUSDC.price AS baseLower, 
        POW(10,12)*POW(1.0001,range.baseUpper)*priceUSDC.price AS baseUpper,  
        POW(10,12)*POW(1.0001,range.limitUpper)*priceUSDC.price AS limitUpper,  
        POW(10,12)*POW(1.0001,range.limitLower)*priceUSDC.price AS limitLower
    FROM range, prices.usd AS priceUSDC
    WHERE priceUSDC.symbol = 'USDC' AND date_trunc('minute', range.time) = date_trunc('minute', priceUSDC.minute)
    ORDER by 1 desc
),

ethPriceEveryHour AS(
    SELECT date_trunc('hour', minute) as time,
       AVG(price) as ethereum_price 
    FROM prices.usd
    WHERE symbol = 'WETH' and minute >= cast('2023-04-28 10:00' as TIMESTAMP)
    GROUP BY 1 
),

rangePriceEveryHour AS(
    SELECT
        d.time,
        avg(d.ethereum_price) as "ethereum_price",
        avg(baseLower) as baseLower, 
        avg(baseUpper) as baseUpper,
        avg(limitLower) as limitLower, 
        avg(limitUpper) as limitUpper 
    FROM ethPriceEveryHour AS d
    LEFT JOIN rangePrice AS r 
    ON date_trunc('hour', r.time) = date_trunc('minute', d.time)
    GROUP BY d.time
    ORDER By time
)

-- select * from rangePrice
SELECT *,baseLower AS "b1(for visualization)" ,baseLower AS "b2(for visualization)" FROM rangePriceEveryHour -- additional two baseLower are for visualization (area chart)