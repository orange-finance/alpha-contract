// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/IPoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";

/**
 * @title PoolManagerDeployer
 * @author Orange Finance
 * @notice base contract of all PoolManagerDeployer
 */
abstract contract PoolManagerDeployer is IPoolManagerDeployer {
    event PoolManagerDeployed(address indexed _poolManager, address indexed _liquidityPool);

    /// @inheritdoc IPoolManagerDeployer
    function deployPoolManager(
        address _token0,
        address _token1,
        address _liquidityPool,
        bytes calldata _setUpData
    ) external virtual returns (IPoolManager);

    /**
     * @notice Hook function called after a pool manager is deployed.
     * this is intended to be used for additional setup of the pool manager from a factory regardless of its implementation.
     */
    function _onPoolManagerDeployed(
        address /* _poolManager */,
        address /* _token0 */,
        address /*_token1 */,
        address /*_liquidityPool */,
        bytes calldata /*_setUpData */
    ) internal virtual {
        revert("Not implemented");
    }
}
