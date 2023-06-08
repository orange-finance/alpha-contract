WITH
  Weth AS (
    SELECT
      minute,
      price AS wethPrice
    FROM
      prices.usd
    WHERE
      symbol = 'WETH'
      AND blockchain = 'arbitrum'
      AND minute >= CAST('2023-04-28 10:00' AS TIMESTAMP)
  ),
  Deposits AS (
    SELECT
      o.evt_block_time,
      o.evt_tx_hash,
      o.caller,
      CAST(t.value AS DOUBLE) / POW(10, 6) AS price,
      o.actionType
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action o,
      erc20_arbitrum.evt_Transfer t
    WHERE
      actionType = 1
      AND o.evt_tx_hash = t.evt_tx_hash
      AND t.contract_address = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8 /* USDC */
      AND t."from" = o.caller
  ),
  Refund AS (
    SELECT
      o.evt_block_time,
      o.evt_tx_hash,
      o.caller,
      CAST(t.value AS DOUBLE) / POW(10, 18) AS price,
      o.actionType
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action o,
      erc20_arbitrum.evt_Transfer t
    WHERE
      actionType = 1
      AND o.evt_tx_hash = t.evt_tx_hash
      AND t.contract_address = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 /* WETH */
      AND o.caller = t.to
  ),
  DepositsMinusRefund AS (
    SELECT
      d.evt_block_time,
      d.evt_tx_hash,
      /* usdc - refunded weth */
      d.price - COALESCE(r.price * w.wethPrice, 0) AS price,
      d.actionType
    FROM
      Weth w,
      Deposits d
      LEFT JOIN Refund r ON d.evt_tx_hash = r.evt_tx_hash
    WHERE
      date_trunc('minute', d.evt_block_time) = date_trunc('minute', w.minute)
  ),
  Withdrawals AS (
    SELECT
      o.evt_block_time,
      o.evt_tx_hash,
      CAST(t.value AS DOUBLE) / POW(10, 6) AS price,
      o.actionType
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action o,
      erc20_arbitrum.evt_Transfer t
    WHERE
      actionType = 2
      AND o.evt_tx_hash = t.evt_tx_hash
      AND t.contract_address = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8 /* USDC */
      AND t.to = o.caller
  ),
  Tvl AS (
    SELECT
      o.evt_block_time,
      o.totalAssets / POW(10, 6) AS tvlValue
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action o
  ),
  All AS (
    SELECT
      t.evt_block_time,
      t.tvlValue,
      d.price,
      d.actionType
    FROM
      Tvl t
      LEFT JOIN (
        SELECT
          *
        FROM
          DepositsMinusRefund
        UNION
        SELECT
          *
        FROM
          Withdrawals
      ) d ON t.evt_block_time = d.evt_block_time
  )
SELECT
  evt_block_time AS "Time",
  tvlValue AS "TVL",
  CASE
    WHEN actionType = 1 THEN price
    WHEN actionType = 2 THEN - price
    ELSE 0
  END AS "Deposit/Withdraw"
FROM
  All