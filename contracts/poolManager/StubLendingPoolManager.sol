// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {ILendingPoolManager} from "@src/interfaces/ILendingPoolManager.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";

error StubLendingPoolManager__NotImplemented();
error StubLendingPoolManager__VaultAlreadySet();
error StubLendingPoolManager__ZeroAddress();

/**
 * @title StubLendingPoolManager
 * @notice Some token pairs are not supported by LendingPool, so we need to use this contract to avoid reverts.
 * It's useful for no hedge strategy that doesn't need to interact with LendingPool.
 */
contract StubLendingPoolManager is ILendingPoolManager, IPoolManager {
    address public vault;

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
    function setVault(address vault_) external {
        if (vault != address(0)) revert StubLendingPoolManager__VaultAlreadySet();
        if (vault_ == address(0)) revert StubLendingPoolManager__ZeroAddress();

        vault = vault_;
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
