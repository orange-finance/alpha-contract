WITH
  /**
   * Calculate Aave cumulative borrow amount
   */
  AaveRepayAndBorrow AS (
    SELECT
      CAST(COALESCE(a1.amount, CAST(0 AS uint256)) AS DOUBLE) / 1000000000000000000 AS borrowEth,
      CAST(COALESCE(a2.amount, CAST(0 AS uint256)) AS DOUBLE) / 1000000000000000000 AS repayEth,
      v.evt_block_time,
      v.evt_tx_hash
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action v
      /* aave */
      LEFT JOIN aave_v3_arbitrum.L2Pool_evt_Borrow a1 ON v.evt_tx_hash = a1.evt_tx_hash
      LEFT JOIN aave_v3_arbitrum.L2Pool_evt_Repay a2 ON v.evt_tx_hash = a2.evt_tx_hash
  ),
  AaveBorrowAmount AS (
    SELECT
      evt_tx_hash,
      evt_block_time,
      SUM(borrowEth) OVER (
        ORDER BY
          evt_block_time
      ) AS sumBorrowEth,
      SUM(repayEth) OVER (
        ORDER BY
          evt_block_time
      ) AS sumRepayEth,
      SUM(borrowEth) OVER (
        ORDER BY
          evt_block_time
      ) - SUM(repayEth) OVER (
        ORDER BY
          evt_block_time
      ) AS borrowAmount
    FROM
      AaveRepayAndBorrow
  ),
  /**
   * Get ticks and liquidity for Uniswap
   * by joining Vault's rebalance events AND Uniswap's mint events
   */
  Ticks AS (
    SELECT
      u.evt_block_time,
      u.tickLower,
      u.tickUpper,
      CASE
        WHEN a.borrowAmount < 0 THEN 0
        ELSE a.borrowAmount
      END AS borrowEth,
      /* if minus, 0 */ CAST(u.amount0 AS DOUBLE) / 1000000000000000000 AS liquidityEth
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action v,
      uniswap_v3_arbitrum.Pair_evt_Mint u,
      AaveBorrowAmount a
    WHERE
      v.actionType = 3
      AND v.evt_tx_hash = u.evt_tx_hash
      AND v.evt_tx_hash = a.evt_tx_hash
  ),
  /* Ticks to prices */
  RangePrice AS (
    SELECT
      t.evt_block_time AS blockTime,
      POW(10, 12) * POW(1.0001, t.tickLower) * p.price AS lowerPrice,
      POW(10, 12) * POW(1.0001, t.tickUpper) * p.price AS upperPrice,
      t.borrowEth,
      t.liquidityEth
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
      AVG(upperPrice) AS upperPrice,
      AVG(borrowEth) AS borrowEth,
      AVG(liquidityEth) AS liquidityEth
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
      ) as upperPrice,
      COALESCE(
        r.borrowEth,
        LAST_VALUE(r.borrowEth) IGNORE NULLS OVER (
          ORDER BY
            e.hourTime
        )
      ) as borrowEth,
      COALESCE(
        r.liquidityEth,
        LAST_VALUE(r.liquidityEth) IGNORE NULLS OVER (
          ORDER BY
            e.hourTime
        )
      ) as liquidityEth
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
  lowerPrice AS "b2(for visualization)",
  borrowEth / liquidityEth AS "Hedge Ratio"
FROM
  RangeAndEthPrice