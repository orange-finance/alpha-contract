// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {AddressHelperV2} from "../utils/AddressHelper.sol";

import {IAlgebraPool} from "../../../contracts/vendor/algebra/IAlgebraPool.sol";
import {IAlgebraMintCallback} from "../../../contracts/vendor/algebra/callback/IAlgebraMintCallback.sol";
import {IAlgebraSwapCallback} from "../../../contracts/vendor/algebra/callback/IAlgebraSwapCallback.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../contracts/libs/uniswap/LiquidityAmounts.sol";
import "../../../contracts/libs/uniswap/OracleLibrary.sol";
import "../../../contracts/libs/uniswap/TickMath.sol";

contract CamelotTest is BaseTest, IAlgebraMintCallback, IAlgebraSwapCallback {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using Ints for int24;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelperV2.CamelotAddr camelotAddr;

    IAlgebraPool pool;
    IERC20 weth;
    IERC20 usdc;

    int24 lowerTick = -225180;
    int24 upperTick = -184200;

    function setUp() public {
        (tokenAddr, , ) = AddressHelper.addresses(block.chainid);
        (camelotAddr) = AddressHelperV2.addresses(block.chainid);

        pool = IAlgebraPool(camelotAddr.wethUsdcPoolAddr);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);

        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        weth.safeApprove(address(pool), type(uint256).max);
        usdc.safeApprove(address(pool), type(uint256).max);
    }

    function test_setTick() public view {
        (, int24 _currentTick, , , , , ) = pool.globalState();
        console2.log(_currentTick.toString(), "tick");
    }

    function test_viewFunctions_success() public {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.globalState();
        console2.log(sqrtRatioX96, "sqrtRatioX96");
        console2.log(tick.toString(), "tick");
        console2.log(tick.getSqrtRatioAtTick(), "tickToSqrt");

        uint256 feeGrowthGlobal0 = pool.totalFeeGrowth0Token();
        uint256 feeGrowthGlobal1 = pool.totalFeeGrowth1Token();
        console2.log(feeGrowthGlobal0, "feeGrowthGlobal0");
        console2.log(feeGrowthGlobal1, "feeGrowthGlobal1");
        int24 _lowerTick = tick - 60;
        int24 _upperTick = tick + 60;
        console2.log(_lowerTick.toString(), "lowerTick");
        console2.log(_upperTick.toString(), "upperTick");
        (, , uint256 feeGrowthOutsideLower, , , , , , ) = pool.ticks(_lowerTick);
        (, , uint256 feeGrowthOutsideUpper, , , , , , ) = pool.ticks(_upperTick);
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
        (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        console2.log(liquidity, "liquidity");

        //mint
        (, , uint128 liquidity1) = pool.mint(address(this), address(this), lowerTick, upperTick, liquidity, "");
        console2.log(liquidity1, "liquidity1");
        //assertion
        assertEq(liquidity1, liquidity);

        bytes32 key;
        address owner = address(this);
        int24 bottomTick = lowerTick;
        int24 topTick = upperTick;
        assembly {
            key := or(shl(24, or(shl(24, owner), and(bottomTick, 0xFFFFFF))), and(topTick, 0xFFFFFF))
        }
        (uint256 liquidity_, , , , ) = pool.positions(key);
        console2.log(liquidity_, "liquidity_");
        assertEq(liquidity_, liquidity);
    }

    function test_computeMintAmounts_success() public {
        uint256 amount0 = 1 ether;
        uint256 amount1 = 2000 * 1e6;
        (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();

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

        (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
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

        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.globalState();
        console2.log(tick.toString(), "tick");

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        console2.log(liquidity, "liquidity");

        (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            liquidity
        );
        console2.log(amount0_, "amount0_");
        console2.log(amount1_, "amount1_");

        uint256 quoteAmount = OracleLibrary.getQuoteAtTick(tick, uint128(amount0_), address(weth), address(usdc));
        console2.log("quoteAmount", quoteAmount);

        uint256 _targetLiquidity = FullMath.mulDiv(amount1, liquidity, quoteAmount + amount1_);
        console2.log(_targetLiquidity, "_targetLiquidity");
        (uint256 targetAmount0, uint256 targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            uint128(_targetLiquidity)
        );
        console2.log(targetAmount0, "targetAmount0");
        console2.log(targetAmount1, "targetAmount1");

        pool.mint(address(this), address(this), lowerTick, upperTick, uint128(_targetLiquidity), "");
        assertApproxEqAbs(weth.balanceOf(address(this)), 10000 ether - targetAmount0, 1);
        assertApproxEqAbs(usdc.balanceOf(address(this)), 10_000_000 * 1e6 - targetAmount1, 1);
    }

    function test_burnAndCollect_success() public {
        uint256 amount0 = 1 ether;
        uint256 amount1 = 2000 * 1e6;
        (uint160 sqrtRatioX96, , , , , , ) = pool.globalState();
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        //mint
        pool.mint(address(this), address(this), lowerTick, upperTick, liquidity, "");
        //burn half
        pool.burn(lowerTick, upperTick, liquidity / 2);
        pool.collect(address(this), lowerTick, upperTick, type(uint128).max, type(uint128).max);

        bytes32 key;
        address owner = address(this);
        int24 bottomTick = lowerTick;
        int24 topTick = upperTick;
        assembly {
            key := or(shl(24, or(shl(24, owner), and(bottomTick, 0xFFFFFF))), and(topTick, 0xFFFFFF))
        }
        (uint256 liquidity_, , , , ) = pool.positions(key);
        assertEq(liquidity_, liquidity / 2);
        assertApproxEqRel(weth.balanceOf(address(this)), 10_000 ether - (1 ether / 2), 1e15);
        assertApproxEqRel(usdc.balanceOf(address(this)), 10_000_000 * 1e6 - ((2000 * 1e6) / 2), 1e15);
        console2.log("weth", weth.balanceOf(address(this)));
        console2.log("usdc", usdc.balanceOf(address(this)));

        //burn all
        pool.burn(lowerTick, upperTick, uint128(liquidity_));
        (uint256 liquidity__, , , , ) = pool.positions(key);
        assertEq(liquidity__, 0);
        pool.collect(address(this), lowerTick, upperTick, type(uint128).max, type(uint128).max);
        assertApproxEqAbs(weth.balanceOf(address(this)), 10_000 ether, 2);
        assertApproxEqAbs(usdc.balanceOf(address(this)), 10_000_000 * 1e6, 2);
        console2.log("weth", weth.balanceOf(address(this)));
        console2.log("usdc", usdc.balanceOf(address(this)));
    }

    function test_swap_success() public {
        bool zeroForOne = true;
        int256 swapAmount = 10 ether;
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.globalState();
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
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.globalState();

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
        assertEq(usdc.balanceOf(address(this)), 10_000_000 * 1e6 - uint256(swapAmount));
    }

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function algebraMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata /*_data*/) external override {
        console2.log("algebraMintCallback");
        console2.log(uint256(amount0Owed), uint256(amount1Owed));
        require(msg.sender == address(pool), "callback caller");

        if (amount0Owed > 0) weth.safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) usdc.safeTransfer(msg.sender, amount1Owed);
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata /*data*/) external override {
        console2.log("algebraSwapCallback");
        // console2.log(uint256(amount0Delta), uint256(amount1Delta));
        require(msg.sender == address(pool), "callback caller");
        if (amount0Delta > 0) weth.safeTransfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0) usdc.safeTransfer(msg.sender, uint256(amount1Delta));
    }
}
