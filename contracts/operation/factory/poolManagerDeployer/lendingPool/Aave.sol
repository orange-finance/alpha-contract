// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {PoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/PoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";
import {AaveLendingPoolManager} from "@src/poolManager/AaveLendingPoolManager.sol";

/**
 * @title AaveLendingPoolManagerDeployer
 * @author Orange Finance
 * @notice Deploys AaveLendingPoolManager contracts in a way of OrangeVaultFactory
 */
contract AaveLendingPoolManagerDeployer is PoolManagerDeployer {
    /// @inheritdoc PoolManagerDeployer
    function deployPoolManager(
        address _token0,
        address _token1,
        address _liquidityPool,
        bytes calldata
    ) external override returns (IPoolManager) {
        AaveLendingPoolManager poolManager = new AaveLendingPoolManager({
            _token0: _token0,
            _token1: _token1,
            _aave: _liquidityPool
        });

        emit PoolManagerDeployed(address(poolManager), _liquidityPool);

        return IPoolManager(address(poolManager));
    }
}
