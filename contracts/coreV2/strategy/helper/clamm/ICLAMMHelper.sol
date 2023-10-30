// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface ICLAMMHelper {
    function getTwap(address pool, uint32 minute) external view returns (int24 avgTick);

    function getCurrentTick(address pool) external view returns (int24 tick);

    function getCurrentLiquidity(
        address pool,
        int24 lowerTick,
        int24 upperTick
    ) external view returns (uint128 liquidity);

    function getFeesEarned(
        address pool,
        int24 lowerTick,
        int24 upperTick
    ) external view returns (uint256 fee0, uint256 fee1);

    function getAmountsForLiquidity(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external view returns (uint256 amount0, uint256 amount1);

    function getLiquidityForAmounts(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) external view returns (uint128 liquidity);

    function validateTicks(address pool, int24 lowerTick, int24 upperTick) external view;

    function mint(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(int24 lowerTick, int24 upperTick) external returns (uint128 amount0, uint128 amount1);

    function burn(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    function burnAndCollect(
        address pool,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external returns (uint256, uint256);
}
