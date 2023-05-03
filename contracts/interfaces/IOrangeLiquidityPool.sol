// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

// forked and modified from https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolActions.sol

interface IOrangeLiquidityPool {
    struct Params {
        address token0;
        address token1;
        int24 lowerTick;
        int24 upperTick;
    }

    struct ParamsOfLiquidity {
        address token0;
        address token1;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }

    struct ParamsOfAmount {
        address token0;
        address token1;
        int24 lowerTick;
        int24 upperTick;
        uint256 amount0;
        uint256 amount1;
    }

    struct MintParams {
        address token0;
        address token1;
        address receiver;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
    }

    function getCurrentLiquidity(int24 lowerTick, int24 upperTick) external view returns (uint128 liquidity);

    function getFeesEarned(Params calldata params) external view returns (uint256 fee0, uint256 fee1);

    function getAmountsForLiquidity(
        ParamsOfLiquidity calldata params
    ) external view returns (uint256 amount0, uint256 amount1);

    function getLiquidityForAmounts(ParamsOfAmount calldata params) external view returns (uint128 liquidity);

    function mint(MintParams calldata params) external returns (uint256 amount0, uint256 amount1);

    function collect(Params calldata params) external returns (uint128 amount0, uint128 amount1);

    function burn(ParamsOfLiquidity calldata params) external returns (uint256 amount0, uint256 amount1);
}
