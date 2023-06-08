WITH
  /**
   * Get ticks
   * by joining Vault's rebalance events AND Uniswap's mint events
   */
  Ticks AS (
    SELECT
      u.tickLower,
      u.tickUpper,
      u.evt_block_time
    FROM
      uniswap_v3_arbitrum.Pair_evt_Mint u,
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action v
    WHERE
      v.actionType = 3
      AND u.evt_tx_hash = v.evt_tx_hash
  ),
  /* Ticks to prices */
  RangePrice AS (
    SELECT
      t.evt_block_time AS blockTime,
      POW(10, 12) * POW(1.0001, t.tickLower) * p.price AS lowerPrice,
      POW(10, 12) * POW(1.0001, t.tickUpper) * p.price AS upperPrice
    FROM
      Ticks t,
      prices.usd p
    WHERE
      p.symbol = 'USDC'
      AND date_trunc('minute', t.evt_block_time) = date_trunc('minute', p.minute)
  ),
  /* Grouping tick prices by per hour */
  RangePricePerHour AS (
    SELECT
      date_trunc('hour', blockTime) AS hourTime,
      AVG(lowerPrice) AS lowerPrice,
      AVG(upperPrice) AS upperPrice
    FROM
      RangePrice
    GROUP BY
      1
  ),
  EthPricePerHour AS (
    SELECT
      date_trunc('hour', minute) AS hourTime,
      AVG(price) AS ethPrice
    FROM
      prices.usd
    WHERE
      symbol = 'WETH'
      AND minute >= CAST('2023-04-28 10:00' AS TIMESTAMP)
    GROUP BY
      1
  ),
  /* Left join and if range price is null, fill last price */
  RangeAndEthPrice AS (
    SELECT
      e.hourTime,
      e.ethPrice AS ethPrice,
      COALESCE(
        r.lowerPrice,
        LAST_VALUE(r.lowerPrice) IGNORE NULLS OVER (
          ORDER BY
            e.hourTime
        )
      ) as lowerPrice,
      COALESCE(
        r.upperPrice,
        LAST_VALUE(r.upperPrice) IGNORE NULLS OVER (
          ORDER BY
            e.hourTime
        )
      ) as upperPrice
    FROM
      EthPricePerHour AS e
      LEFT JOIN RangePricePerHour AS r ON e.hourTime = r.hourTime
  )
SELECT
  hourTime,
  ethPrice AS "ETH Price",
  lowerPrice AS "Lower Range",
  upperPrice AS "Upper Range",
  lowerPrice AS "b1(for visualization)",
  lowerPrice AS "b2(for visualization)"
FROM
  RangeAndEthPrice