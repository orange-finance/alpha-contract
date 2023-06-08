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
  ),
  Price AS (
    SELECT
      Vault.evt_block_time AS blockTime,
      -- CAST(Vault.totalAssets AS DOUBLE) AS totalAssets,
      -- CAST(Vault.totalSupply AS DOUBLE) AS totalSupply,
      CAST(Vault.totalAssets AS DOUBLE) / CAST(Vault.totalSupply AS DOUBLE) AS valuePerShare,
      Weth.wethPrice AS wethPrice
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action Vault
      LEFT JOIN Weth ON date_trunc('minute', Vault.evt_block_time) = date_trunc('minute', Weth.minute)
    WHERE
      Vault.totalSupply > CAST(0 AS UINT256)
      AND date_trunc('minute', Vault.evt_block_time) >= CAST('2023-05-12 09:00' AS TIMESTAMP)
  ),
  BasisPrice AS (
    SELECT
      *
    FROM
      Price
    ORDER BY
      blockTime
    LIMIT
      1
  )
SELECT
  Price.blockTime AS Time,
  Price.valuePerShare / BasisPrice.valuePerShare AS "Vault Performance",
  Price.wethPrice / BasisPrice.wethPrice AS "ETH HODL Performance",
  1 AS "USDC HODL Performance"
FROM
  Price,
  BasisPrice