// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import "../../../contracts/vendor/uniswap/LiquidityAmounts.sol";
import "../../../contracts/vendor/uniswap/OracleLibrary.sol";
import "../../../contracts/vendor/uniswap/TickMath.sol";

contract UniswapV3Test is
    BaseTest,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback
{
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using Ints for int24;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    IUniswapV3Pool pool;
    IERC20 weth;
    IERC20 usdc;

    int24 lowerTick = -225180;
    int24 upperTick = -184200;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);

        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        weth.safeApprove(address(pool), type(uint256).max);
        usdc.safeApprove(address(pool), type(uint256).max);
    }

    function test_viewFunctions_success() public {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
        console2.log(sqrtRatioX96, "sqrtRatioX96");
        console2.log(tick.toString(), "tick");
        console2.log(tick.getSqrtRatioAtTick(), "tickToSqrt");

        uint256 feeGrowthGlobal0 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1 = pool.feeGrowthGlobal1X128();
        console2.log(feeGrowthGlobal0, "feeGrowthGlobal0");
        console2.log(feeGrowthGlobal1, "feeGrowthGlobal1");
        int24 _lowerTick = tick - 60;
        int24 _upperTick = tick + 60;
        console2.log(_lowerTick.toString(), "lowerTick");
        console2.log(_upperTick.toString(), "upperTick");
        (, , uint256 feeGrowthOutsideLower, , , , , ) = pool.ticks(_lowerTick);
        (, , uint256 feeGrowthOutsideUpper, , , , , ) = pool.ticks(_upperTick);
        console2.log(feeGrowthOutsideLower, "feeGrowthOutsideLower");
        console2.log(feeGrowthOutsideUpper, "feeGrowthOutsideUpper");

        // uint32[] memory secondsAgo = new uint32[](2);
        // secondsAgo[0] = 5 minutes;
        // secondsAgo[1] = 0;
        // (int56[] memory tickCumulatives, ) = pool.observe(secondsAgo);
    }

    function test_mint_success() public {
        int24 spac = pool.tickSpacing();
        console2.log(spac.toString(), "tickSpacing");

        uint256 amount0 = 1 ether;
        uint256 amount1 = 2000 * 1e6;
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        //mint
        pool.mint(address(this), lowerTick, upperTick, liquidity, "");
        //assertion
        bytes32 positionID = keccak256(
            abi.encodePacked(address(this), lowerTick, upperTick)
        );
        (uint128 liquidity_, , , , ) = pool.positions(positionID);
        assertEq(liquidity_, liquidity);
        console2.log(liquidity_, "liquidity_");
    }

    function test_computeMintAmounts_success() public {
        uint256 amount0 = 1 ether;
        uint256 amount1 = 2000 * 1e6;
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();

        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
            sqrtRatioX96,
            upperTick.getSqrtRatioAtTick(),
            amount0
        );
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            lowerTick.getSqrtRatioAtTick(),
            sqrtRatioX96,
            amount1
        );
        uint128 liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;

        (uint256 amount0_, uint256 amount1_) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                liquidity
            );
        console2.log(amount0_, "amount0");
        console2.log(amount1_, "amount1");
    }

    function test_mintAndSwap_success() public {
        uint256 amount0 = 100 ether;
        uint256 amount1 = 2000 * 1e6;

        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
        console2.log(tick.toString(), "tick");

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        console2.log(liquidity, "liquidity");

        (uint256 amount0_, uint256 amount1_) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                liquidity
            );
        console2.log(amount0_, "amount0_");
        console2.log(amount1_, "amount1_");

        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
            tick,
            uint128(amount0_),
            address(weth),
            address(usdc)
        );
        console2.log("quoteAmount", quoteAmount);

        uint256 _targetLiquidity = FullMath.mulDiv(
            amount1,
            liquidity,
            quoteAmount + amount1_
        );
        console2.log(_targetLiquidity, "_targetLiquidity");
        (uint256 targetAmount0, uint256 targetAmount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                uint128(_targetLiquidity)
            );
        console2.log(targetAmount0, "targetAmount0");
        console2.log(targetAmount1, "targetAmount1");

        pool.mint(
            address(this),
            lowerTick,
            upperTick,
            uint128(_targetLiquidity),
            ""
        );
        assertApproxEqAbs(
            weth.balanceOf(address(this)),
            10000 ether - targetAmount0,
            1
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(this)),
            10_000_000 * 1e6 - targetAmount1,
            1
        );
    }

    function test_burnAndCollect_success() public {
        uint256 amount0 = 1 ether;
        uint256 amount1 = 2000 * 1e6;
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        //mint
        pool.mint(address(this), lowerTick, upperTick, liquidity, "");
        //burn half
        pool.burn(lowerTick, upperTick, liquidity / 2);
        pool.collect(
            address(this),
            lowerTick,
            upperTick,
            type(uint128).max,
            type(uint128).max
        );
        bytes32 positionID = keccak256(
            abi.encodePacked(address(this), lowerTick, upperTick)
        );
        (uint128 liquidity_, , , , ) = pool.positions(positionID);
        assertEq(liquidity_, liquidity / 2);
        assertApproxEqRel(
            weth.balanceOf(address(this)),
            10_000 ether - (1 ether / 2),
            1e15
        );
        assertApproxEqRel(
            usdc.balanceOf(address(this)),
            10_000_000 * 1e6 - ((2000 * 1e6) / 2),
            1e15
        );
        console2.log("weth", weth.balanceOf(address(this)));
        console2.log("usdc", usdc.balanceOf(address(this)));

        //burn all
        pool.burn(lowerTick, upperTick, liquidity_);
        (uint128 liquidity__, , , , ) = pool.positions(positionID);
        assertEq(liquidity__, 0);
        pool.collect(
            address(this),
            lowerTick,
            upperTick,
            type(uint128).max,
            type(uint128).max
        );
        assertApproxEqAbs(weth.balanceOf(address(this)), 10_000 ether, 2);
        assertApproxEqAbs(usdc.balanceOf(address(this)), 10_000_000 * 1e6, 2);
        console2.log("weth", weth.balanceOf(address(this)));
        console2.log("usdc", usdc.balanceOf(address(this)));
    }

    function test_swap_success() public {
        bool zeroForOne = true;
        int256 swapAmount = 10 ether;
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
        console2.log(sqrtRatioX96, "sqrtRatioX96");

        uint160 swapThresholdPrice = TickMath.getSqrtRatioAtTick(tick - 30);
        console2.log(swapThresholdPrice, "swapThresholdPrice");

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            zeroForOne,
            swapAmount,
            swapThresholdPrice, //sqrtPriceLimitX96
            "" //data
        );
        console2.log("testPoolSwap");
        console2.log(uint256(amount0Delta), uint256(amount1Delta));
        console2.log("weth", weth.balanceOf(address(this)));
        assertEq(weth.balanceOf(address(this)), 9990 ether);
        console2.log("usdc", usdc.balanceOf(address(this)));
    }

    function test_swapReverse_success() public {
        bool zeroForOne = false;
        int256 swapAmount = 1_000 * 1e6;
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();

        uint160 swapThresholdPrice = TickMath.getSqrtRatioAtTick(tick + 30);
        console2.log("swapThresholdPrice", swapThresholdPrice);

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this),
            zeroForOne,
            swapAmount,
            swapThresholdPrice, //sqrtPriceLimitX96
            "" //data
        );
        console2.log("testPoolSwap");
        console2.log(uint256(amount0Delta), uint256(amount1Delta));
        console2.log("weth", weth.balanceOf(address(this)));
        console2.log("usdc", usdc.balanceOf(address(this)));
        assertEq(
            usdc.balanceOf(address(this)),
            10_000_000 * 1e6 - uint256(swapAmount)
        );
    }

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        console2.log("uniswapV3MintCallback");
        console2.log(uint256(amount0Owed), uint256(amount1Owed));
        require(msg.sender == address(pool), "callback caller");

        if (amount0Owed > 0) weth.safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) usdc.safeTransfer(msg.sender, amount1Owed);
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external override {
        console2.log("uniswapV3SwapCallback");
        // console2.log(uint256(amount0Delta), uint256(amount1Delta));
        require(msg.sender == address(pool), "callback caller");
        if (amount0Delta > 0)
            weth.safeTransfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0)
            usdc.safeTransfer(msg.sender, uint256(amount1Delta));
    }
}
