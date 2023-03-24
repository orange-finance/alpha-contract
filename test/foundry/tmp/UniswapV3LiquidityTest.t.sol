// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../../../contracts/libs/uniswap/LiquidityAmounts.sol";
import "../../../contracts/libs/uniswap/OracleLibrary.sol";
import "../../../contracts/libs/uniswap/TickMath.sol";

contract UniswapV3LiquidityTest is BaseTest {
    using TickMath for int24;
    using Ints for int24;

    function setUp() public {}

    function test_getLiquidityAmount1() public {
        int24 tick0 = -207243; // 1ETH=1000USDC
        int24 lowerTick = -208297;
        int24 upperTick = -206290;

        uint256 amount0 = 1 ether;
        uint256 amount1 = 1000 * 1e6;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            tick0.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        console2.log(liquidity, "liquidity");

        (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
            tick0.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            liquidity
        );
        console2.log(amount0_, "amount0_");
        console2.log(amount1_, "amount1_");

        //price down
        tick0 = -214175; //1ETH = 500USDC
        (amount0_, amount1_) = LiquidityAmounts.getAmountsForLiquidity(
            tick0.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            liquidity
        );
        console2.log(amount0_, "amount0_");
        console2.log(amount1_, "amount1_");

        //price up
        tick0 = -203188; //1ETH = 1500USDC
        (amount0_, amount1_) = LiquidityAmounts.getAmountsForLiquidity(
            tick0.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            liquidity
        );
        console2.log(amount0_, "amount0_");
        console2.log(amount1_, "amount1_");
    }
}
