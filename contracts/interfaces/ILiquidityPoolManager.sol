// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

// forked and modified from https://github.com/Uniswap/v3-core/blob/main/contracts/interfaces/pool/IUniswapV3PoolActions.sol
interface ILiquidityPoolManager {
    function getTwap(uint32 _minute) external view returns (int24 avgTick);

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

    function getPoolAddress() external view returns (address poolAddress);

    function validateTicks(int24 _lowerTick, int24 _upperTick) external view;

    function mint(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(int24 lowerTick, int24 upperTick) external returns (uint128 amount0, uint128 amount1);

    function burn(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    function burnAndCollect(int24 _lowerTick, int24 _upperTick, uint128 _liquidity) external returns (uint256, uint256);
}
