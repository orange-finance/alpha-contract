SELECT
  o.evt_block_time AS blockTime,
  o.totalAssets / POW(10, 6) AS TVL
FROM
  orange_finance_arbitrum.OrangeAlphaVault_evt_Action o