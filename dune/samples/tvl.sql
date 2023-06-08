with deposits as (
select t.contract_address, a.evt_block_time, a.evt_block_number, a.evt_tx_hash, cast(t.value as double) / POW(10, 6) as value, actionType, caller
from orange_finance_arbitrum.OrangeAlphaVault_evt_Action a
left join erc20_arbitrum.evt_Transfer t
on a.evt_tx_hash = t.evt_tx_hash and a.evt_block_number = t.evt_block_number and caller = "from" and actionType = 1
),
withdrawals as (
select t.contract_address, a.evt_block_time, a.evt_block_number, a.evt_tx_hash, -cast(t.value as double) / POW(10, 6) as value, actionType, caller
from orange_finance_arbitrum.OrangeAlphaVault_evt_Action a
left join erc20_arbitrum.evt_Transfer t
on a.evt_tx_hash = t.evt_tx_hash and a.evt_block_number = t.evt_block_number and caller = "to" and actionType = 2
)
-- do a deposit actionType = 1) for erc20 tokens FROM the user who initiatied it
-- minus the redeem actionType = 2 for erc20 tokens going TO the end user "from" who initiated it

SELECT evt_block_time, round(sum(value) ,2) as change, round(sum(sum(value)) over(order by evt_block_time), 2) as TVL_usdc
from (
    select * from deposits
    UNION
    select * from withdrawals
)
where actionType in (1,2)
group by evt_block_time
order by evt_block_time desc