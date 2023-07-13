WITH
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
  HedgeRatio AS (
    SELECT
      a.borrowAmount AS borrowEth,
      CAST(u.amount0 AS DOUBLE) / 1000000000000000000 AS liquidityEth,
      v.evt_block_time,
      v.evt_tx_hash
    FROM
      orange_finance_arbitrum.OrangeAlphaVault_evt_Action v,
      uniswap_v3_arbitrum.Pair_evt_Mint u,
      AaveBorrowAmount a
    WHERE
      v.actionType = 3
      AND v.evt_tx_hash = u.evt_tx_hash
      AND v.evt_tx_hash = a.evt_tx_hash
  )
SELECT
  *,
  borrowEth / liquidityEth * 100 AS hedgeRatio
FROM
  HedgeRatio