// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../../../contracts/libs/uniswap/LiquidityAmounts.sol";
import "../../../contracts/libs/uniswap/OracleLibrary.sol";
import "../../../contracts/libs/uniswap/TickMath.sol";

contract LiquidityAmountsTest is BaseTest {
  using TickMath for int24;
  using Ints for int24;

  AddressHelper.TokenAddr public tokenAddr;
  AddressHelper.UniswapAddr uniswapAddr;

  IUniswapV3Pool pool;
  IERC20 weth;
  IERC20 usdc;

  function setUp() public {
    (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

    pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
    weth = IERC20(tokenAddr.wethAddr);
    usdc = IERC20(tokenAddr.usdcAddr);
  }

  function test_getSqrtRatioAtTick() public {
    console2.log(TickMath.getSqrtRatioAtTick(-265680), "265680");
    console2.log(TickMath.getSqrtRatioAtTick(-143760), "143760");
  }

  function test_getLiquidityByAmount_success() public {
    (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
    // -204720
    int24 lowerTick = -184230;
    int24 upperTick = -225180;

    uint256 amount0 = 1 ether;
    uint256 amount1 = 1200 * 1e6;

    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtRatioX96,
      lowerTick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      amount0,
      amount1
    );
    // console2.log(liquidity, "liquidity");

    (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtRatioX96,
      lowerTick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      liquidity
    );
    console2.log(amount0_, "amount0_");
    console2.log(amount1_, "amount1_");

    uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
      lowerTick.getSqrtRatioAtTick(),
      tick.getSqrtRatioAtTick(),
      amount0
    );
    // console2.log(liquidity0, "liquidity0");

    uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
      tick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      amount1
    );
    // console2.log(liquidity1, "liquidity1");
  }

  function test_getLiquidityByUsdc_success() public {
    uint256 amount1 = 2000 * 1e6;

    (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
    console2.log(tick.toString(), "tick");

    int24 lowerTick = -225180;
    // int24 lowerTick = -204720;
    int24 upperTick = -184230;
    // int24 upperTick = -204720;

    uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
      sqrtRatioX96,
      lowerTick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      100 ether,
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
  }

  function test_getLiquidity_success() public {
    (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
    // -204720
    int24 lowerTick = -184230;
    int24 upperTick = -225180;

    uint256 amount0 = 10 ether;
    uint128 liquidity = LiquidityAmounts.getLiquidityForAmount0(
      lowerTick.getSqrtRatioAtTick(),
      tick.getSqrtRatioAtTick(),
      amount0
    );
    console2.log(liquidity, "liquidity");
    uint256 amount0_ = LiquidityAmounts.getAmount0ForLiquidity(
      lowerTick.getSqrtRatioAtTick(),
      tick.getSqrtRatioAtTick(),
      liquidity
    );
    console2.log(amount0_, "amount0_");
    assertApproxEqRel(amount0, amount0_, 1e15);

    uint256 amount1_ = LiquidityAmounts.getAmount1ForLiquidity(
      tick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      liquidity
    );
    console2.log(amount1_, "amount1_");
    uint128 liquidity_ = LiquidityAmounts.getLiquidityForAmount1(
      tick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      amount1_
    );
    console2.log(liquidity_, "liquidity_");
    assertApproxEqRel(liquidity, liquidity_, 1e15);

    (uint256 amount0__, uint256 amount1__) = LiquidityAmounts.getAmountsForLiquidity(
      sqrtRatioX96,
      lowerTick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      liquidity
    );
    console2.log(amount0__, "amount0__");
    console2.log(amount1__, "amount1__");

    uint128 liquidity__ = LiquidityAmounts.getLiquidityForAmounts(
      sqrtRatioX96,
      lowerTick.getSqrtRatioAtTick(),
      upperTick.getSqrtRatioAtTick(),
      amount0__,
      amount1__
    );
    console2.log(liquidity__, "liquidity__");
    assertApproxEqRel(liquidity, liquidity__, 1e15);
  }
}
