WITH Price AS(
    SELECT 
        (snapshot."totalAmount0"*priceWETH.price + snapshot."totalAmount1"*priceUSDT.price*10^12) / snapshot."totalSupply" AS PricePerShare, 
        priceWETH.price AS PriceWETH, 
        evt_block_time as Time
    FROM charm."AlphaVault_evt_Snapshot" AS snapshot, prices.usd AS priceWETH, prices.usd AS priceUSDT
    WHERE 
        snapshot.contract_address = '\xE72f3E105e475D7Db3a003FfA377aFAe9c2c6c11' 
        AND priceWETH.symbol = 'WETH' AND date_trunc('minute', snapshot.evt_block_time) = priceWETH.minute 
        AND priceUSDT.symbol = 'USDT' AND date_trunc('minute', snapshot.evt_block_time) = priceUSDT.minute
        AND date_trunc('day', snapshot.evt_block_time) >= (date_trunc('day', NOW()) - interval '{{Number of days}} days')
),

basisPrice AS(
    SELECT *
    FROM Price
    ORDER BY time ASC LIMIT 1
)

SELECT
    Price.time AS Time,
    Price.PricePerShare / basisPrice.PricePerShare AS "Vault Performance",
    Price.PriceWETH / basisPrice.PriceWETH AS "ETH HODL Performance",
    sqrt(Price.PriceWETH) / sqrt(basisPrice.PriceWETH) AS "V2 LP Performance Without Fee (sqrt_ETH)",
    1 AS "USDT HODL Performance"
FROM 
    Price, basisPrice