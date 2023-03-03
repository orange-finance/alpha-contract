// SPDX-License-Identifier: UNLICENSED
//forked and minimize from https://github.com/gelatodigital/ops/blob/f6c45c81971c36e414afc31276481c47e202bdbf/contracts/integrations/OpsReady.sol
pragma solidity ^0.8.0;

import {IAaveV3Pool} from "../interfaces/IAaveV3Pool.sol";

/**
 * @dev Inherit this contract to allow your smart contract to
 * - Make synchronous fee payments.
 * - Have call restrictions for functions to be automated.
 */
library SafeAavePool {
    string constant AAVE_MISMATCH = "AAVE_MISMATCH";

    function safeSupply(
        IAaveV3Pool pool,
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        if (amount > 0) {
            pool.supply(asset, amount, onBehalfOf, referralCode);
        }
    }

    function safeWithdraw(
        IAaveV3Pool pool,
        address asset,
        uint256 amount,
        address to
    ) external {
        if (amount > 0) {
            if (amount != pool.withdraw(asset, amount, to)) {
                revert(AAVE_MISMATCH);
            }
        }
    }

    function safeBorrow(
        IAaveV3Pool pool,
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external {
        if (amount > 0) {
            pool.borrow(
                asset,
                amount,
                interestRateMode,
                referralCode,
                onBehalfOf
            );
        }
    }

    function safeRepay(
        IAaveV3Pool pool,
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    ) external {
        if (amount > 0) {
            if (
                amount !=
                pool.repay(asset, amount, interestRateMode, onBehalfOf)
            ) {
                revert(AAVE_MISMATCH);
            }
        }
    }
}
