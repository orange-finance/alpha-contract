// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {ILendingPoolManager} from "@src/interfaces/ILendingPoolManager.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";

error StubLendingPoolManager__NotImplemented();

/**
 * @title StubLendingPoolManager
 * @notice Some token pairs are not supported by LendingPool, so we need to use this contract to avoid reverts.
 * It's useful for no hedge strategy that doesn't need to interact with LendingPool.
 */
contract StubLendingPoolManager is ILendingPoolManager, IPoolManager {
    /// @inheritdoc ILendingPoolManager
    function balances() external pure returns (uint256, uint256) {
        return (0, 0);
    }

    /// @inheritdoc ILendingPoolManager
    function balanceOfCollateral() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc ILendingPoolManager
    function balanceOfDebt() external pure returns (uint256) {
        return 0;
    }

    /// @inheritdoc IPoolManager
    function setVault(address) external pure {
        // we leave this empty because factory use this function in deployment.
        // reverting here will cause deployment to fail.
    }

    /// @inheritdoc ILendingPoolManager
    function supply(uint256) external pure {
        revert StubLendingPoolManager__NotImplemented();
    }

    /// @inheritdoc ILendingPoolManager
    function withdraw(uint256) external pure {
        revert StubLendingPoolManager__NotImplemented();
    }

    /// @inheritdoc ILendingPoolManager
    function borrow(uint256) external pure {
        revert StubLendingPoolManager__NotImplemented();
    }

    /// @inheritdoc ILendingPoolManager
    function repay(uint256) external pure {
        revert StubLendingPoolManager__NotImplemented();
    }
}
