// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

// forked and modified from https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolActions.sol
interface IUniswapV3LiquidityPoolManager {
    struct MintParams {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }

    struct BurnParams {
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }

    struct CollectParams {
        int24 lowerTick;
        int24 upperTick;
    }

    function pool() external view returns (IUniswapV3Pool);

    function getCurrentTick() external view returns (int24 tick);

    function getCurrentLiquidity(int24 lowerTick, int24 upperTick) external view returns (uint128 liquidity);

    function getFeesEarned(int24 lowerTick, int24 upperTick) external view returns (uint256 fee0, uint256 fee1);

    function getAmountsForLiquidity(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external view returns (uint256 amount0, uint256 amount1);

    function getLiquidityForAmounts(
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) external view returns (uint128 liquidity);

    function validateTicks(int24 _lowerTick, int24 _upperTick) external view;

    function mint(MintParams calldata params) external returns (uint256 amount0, uint256 amount1);

    function collect(CollectParams calldata params) external returns (uint128 amount0, uint128 amount1);

    function burn(BurnParams calldata params) external returns (uint256 amount0, uint256 amount1);
}
