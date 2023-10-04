// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {PoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/PoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";
import {UniswapV3LiquidityPoolManager} from "@src/poolManager/UniswapV3LiquidityPoolManager.sol";

contract UniswapV3LiquidityPoolManagerDeployer is PoolManagerDeployer {
    function deployPoolManager(
        address _token0,
        address _token1,
        address _liquidityPool,
        bytes calldata
    ) external override returns (IPoolManager) {
        UniswapV3LiquidityPoolManager poolManager = new UniswapV3LiquidityPoolManager({
            _token0: _token0,
            _token1: _token1,
            _pool: _liquidityPool
        });

        return IPoolManager(address(poolManager));
    }
}
