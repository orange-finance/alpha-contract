// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0;

import {LiquidityAmounts} from "../libs/uniswap/LiquidityAmounts.sol";
import {TickMath} from "../libs/uniswap/TickMath.sol";

contract LiquidityAmountsMock {
    using TickMath for int24;

    function getSqrtRatioAtTick(int24 _tick) external pure returns (uint160) {
        return _tick.getSqrtRatioAtTick();
    }

    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint128 liquidity) {
        return LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
    }

    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) external pure returns (uint256 amount0, uint256 amount1) {
        return LiquidityAmounts.getAmountsForLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
    }
}
