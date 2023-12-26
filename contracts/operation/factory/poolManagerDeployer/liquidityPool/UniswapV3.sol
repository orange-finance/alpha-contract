// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {PoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/PoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";
import {UniswapV3LiquidityPoolManager} from "@src/poolManager/UniswapV3LiquidityPoolManager.sol";

/**
 * @title UniswapV3LiquidityPoolManagerDeployer
 * @author Orange Finance
 * @notice Deploys UniswapV3LiquidityPoolManager contracts in a way of OrangeVaultFactory
 */
contract UniswapV3LiquidityPoolManagerDeployer is PoolManagerDeployer {
    struct PoolManagerConfig {
        address owner;
        address perfFeeRecipient;
        uint128 perfFeeDivisor;
    }

    /// @inheritdoc PoolManagerDeployer
    function deployPoolManager(
        address token0,
        address token1,
        address liquidityPool,
        bytes calldata setupData
    ) external override returns (IPoolManager) {
        UniswapV3LiquidityPoolManager poolManager = new UniswapV3LiquidityPoolManager({
            _token0: token0,
            _token1: token1,
            _pool: liquidityPool
        });

        emit PoolManagerDeployed(address(poolManager), liquidityPool);

        if (setupData.length > 0)
            _onPoolManagerDeployed(address(poolManager), token0, token1, liquidityPool, setupData);

        return IPoolManager(address(poolManager));
    }

    function _onPoolManagerDeployed(
        address poolManager,
        address,
        address,
        address,
        bytes calldata setupData
    ) internal override {
        PoolManagerConfig memory config = abi.decode(setupData, (PoolManagerConfig));

        if (config.owner == address(0)) revert("ZERO_ADDRESS");

        UniswapV3LiquidityPoolManager _poolManager = UniswapV3LiquidityPoolManager(poolManager);

        // set performance fee if specified
        address _recipient = config.perfFeeRecipient;
        if (_recipient != address(0)) {
            _poolManager.setPerfFeeRecipient(_recipient);
            _poolManager.setPerfFeeDivisor(config.perfFeeDivisor);
        }

        // transfer ownership
        _poolManager.transferOwnership(config.owner);
    }
}
