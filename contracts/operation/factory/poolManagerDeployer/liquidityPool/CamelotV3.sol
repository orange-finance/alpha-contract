// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {PoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/PoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";
import {CamelotV3LiquidityPoolManager} from "@src/poolManager/CamelotV3LiquidityPoolManager.sol";

contract CamelotV3LiquidityPoolManagerDeployer is PoolManagerDeployer {
    function deployPoolManager(
        address _token0,
        address _token1,
        address _liquidityPool,
        bytes calldata
    ) external override returns (IPoolManager) {
        CamelotV3LiquidityPoolManager poolManager = new CamelotV3LiquidityPoolManager({
            _token0: _token0,
            _token1: _token1,
            _pool: _liquidityPool
        });

        return IPoolManager(address(poolManager));
    }
}
