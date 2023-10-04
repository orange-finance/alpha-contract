// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {BaseTest} from "@test/foundry/utils/BaseTest.sol";
import {MockERC20} from "@test/foundry/mocks/MockERC20.sol";
import {MockAaveV3Pool} from "@test/foundry/operation/mocks/vendor/MockAavePool.sol";
import {MockUniswapV3Pool} from "@test/foundry/operation/mocks/vendor/MockUniswapV3Pool.sol";
import {AaveLendingPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/lendingPool/Aave.sol";
import {UniswapV3LiquidityPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/liquidityPool/UniswapV3.sol";
import {CamelotV3LiquidityPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/liquidityPool/CamelotV3.sol";
import {AaveLendingPoolManager} from "@src/poolManager/AaveLendingPoolManager.sol";
import {UniswapV3LiquidityPoolManager} from "@src/poolManager/UniswapV3LiquidityPoolManager.sol";
import {CamelotV3LiquidityPoolManager} from "@src/poolManager/CamelotV3LiquidityPoolManager.sol";

contract Fixture is BaseTest {
    MockERC20 public mockToken0;
    MockERC20 public mockToken1;
    MockAaveV3Pool public mockAaveV3Pool;
    MockUniswapV3Pool public mockUniswapV3Pool;
    AaveLendingPoolManagerDeployer public aaveLendingPoolManagerDeployer;
    UniswapV3LiquidityPoolManagerDeployer public uniswapV3LiquidityPoolManagerDeployer;
    CamelotV3LiquidityPoolManagerDeployer public camelotV3LiquidityPoolManagerDeployer;

    function _deployMockAaveV3Pool() internal {
        mockAaveV3Pool = new MockAaveV3Pool();
    }

    function _deployMockUniswapV3Pool() internal {
        mockUniswapV3Pool = new MockUniswapV3Pool();
    }

    function _deployMockTokens() internal {
        mockToken0 = new MockERC20("MockToken0", "MT0");
        mockToken1 = new MockERC20("MockToken1", "MT1");
    }
}
