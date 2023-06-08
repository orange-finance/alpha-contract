with USDC as (
select minute, price as USDC_price
from prices.usd
where symbol = 'USDC'
and blockchain = 'arbitrum'
),
WETH as (
select minute, price as WETH_price
from prices.usd
where symbol = 'WETH'
and blockchain = 'arbitrum'
),
Price as (
    select
    m.evt_block_time as Time,
    -- t.value (representing vault tokens transferred) is already multiplied by 10^6, so we use that when dividing amount0 and amount1
        (amount0*WETH_price / POW(10, 12) + amount1*USDC_price) / t.value AS PricePerShare, 
        (amount0*WETH_price / POW(10, 18) + amount1*USDC_price / POW(10, 6)) AS TVL,
        WETH_price,
        m.evt_tx_hash
        -- below is for testing
        -- amount0 / POW(10, 18) as amt0,
        -- amount1 / POW(10, 6) as amt1,
        -- WETH_price,
        -- USDC_price,
        -- totalSupply,
    from uniswap_v3_arbitrum.Pair_evt_Mint as m
    left join USDC 
    on date_trunc('minute', m.evt_block_time) = date_trunc('minute', USDC.minute)
    left join WETH 
    on date_trunc('minute', m.evt_block_time) = date_trunc('minute', WETH.minute)
    -- LEFT JOIN orange_finance_arbitrum.OrangeAlphaVault_evt_Action as a
    -- ON a.evt_tx_hash = m.evt_tx_hash
    LEFT JOIN erc20_arbitrum.evt_Transfer t
    on t.contract_address = 0x1c99416c7243563ebEDCBEd91ec8532fF74B9a39
    and t."from" = 0x0000000000000000000000000000000000000000
    and t.evt_tx_hash = m.evt_tx_hash
    WHERE owner = 0x1c99416c7243563ebEDCBEd91ec8532fF74B9a39
    AND t.value >= cast(0 as UINT256) -- this removes tx's that are Orange Alpha rebalances, aka actionType = 3
    AND date_trunc('minute', m.evt_block_time) >= cast('2023-04-28 09:00' as TIMESTAMP) 
),
basisPrice AS (
    SELECT
      *
    FROM
      Price
    ORDER BY
      time
    LIMIT
      1
  )

SELECT
  Price.time AS Time,
  Price.PricePerShare / basisPrice.PricePerShare AS "Vault Performance",
  Price.WETH_price / basisPrice.WETH_price AS "ETH HODL Performance",
  SQRT(Price.WETH_price) / SQRT(basisPrice.WETH_price) AS "V2 LP Performance Without Fee (sqrt_ETH)",
  1 AS "USDC HODL Performance",
  Price.TVL AS tx_tvl
FROM
  Price,
  basisPrice