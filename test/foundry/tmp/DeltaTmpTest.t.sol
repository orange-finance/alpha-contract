// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";

import "../../../contracts/vendor/uniswap/LiquidityAmounts.sol";
import "../../../contracts/vendor/uniswap/OracleLibrary.sol";
import "../../../contracts/vendor/uniswap/TickMath.sol";

contract DeltaTmpTest is BaseTest, IUniswapV3MintCallback {
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

    function test_judgeZeroForOne_success() public {
        (uint160 sqrtRatioX96, , , , , , ) = pool.slot0();
        uint256 amount0 = 333 ether / 1000;
        uint256 amount1 = 428 * 1e6;

        uint128 baseLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            amount0,
            amount1
        );
        if (baseLiquidity > 0) {
            (uint256 amountDeposited0, uint256 amountDeposited1) = pool.mint(
                address(this),
                lowerTick,
                upperTick,
                baseLiquidity,
                ""
            );

            amount0 -= amountDeposited0;
            amount1 -= amountDeposited1;
        }
        console2.log(amount0, "amount0");
        console2.log(amount1, "amount1");
    }

    function test_computeLtv_success() public {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = pool.slot0();
        int24 _lowerTick = -205760;
        int24 _upperTick = -203760;
        console2.log(tick.toString(), "tick");
        // 204714

        uint256 price = OracleLibrary.getQuoteAtTick(
            tick,
            1 ether,
            address(weth),
            address(usdc)
        );
        uint256 priceLower = OracleLibrary.getQuoteAtTick(
            _lowerTick,
            1 ether,
            address(weth),
            address(usdc)
        );
        uint256 priceUpper = OracleLibrary.getQuoteAtTick(
            _upperTick,
            1 ether,
            address(weth),
            address(usdc)
        );
        console2.log(price, "price");
        console2.log(priceLower, "priceLower");
        console2.log(priceUpper, "priceUpper");

        uint256 rangeWidth = priceUpper - priceLower;
        uint256 currentWidth = price - priceLower;
        //range 20%
        uint256 ltv = 85e6 - ((20e6) * currentWidth) / rangeWidth;
        console2.log(rangeWidth, "rangeWidth");
        console2.log(currentWidth, "currentWidth");
        console2.log(ltv, "ltv");
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
}
