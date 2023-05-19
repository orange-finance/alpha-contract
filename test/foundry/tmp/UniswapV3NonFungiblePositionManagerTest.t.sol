// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";

import "../../../contracts/libs/uniswap/LiquidityAmounts.sol";
import "../../../contracts/libs/uniswap/OracleLibrary.sol";
import "../../../contracts/libs/uniswap/TickMath.sol";

contract UniswapV3NonFungiblePositionManagerTest is BaseTest, IUniswapV3MintCallback {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using Ints for int24;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    INonfungiblePositionManager fungible;
    IUniswapV3Pool pool;
    IERC20 weth;
    IERC20 usdc;

    int24 lowerTick = -225180;
    int24 upperTick = -184200;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        fungible = INonfungiblePositionManager(uniswapAddr.nonfungiblePositionManagerAddr);
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr500);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);

        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        weth.safeApprove(address(fungible), type(uint256).max);
        usdc.safeApprove(address(fungible), type(uint256).max);
        weth.safeApprove(address(pool), type(uint256).max);
        usdc.safeApprove(address(pool), type(uint256).max);
    }

    // struct MintParams {
    //     address token0;
    //     address token1;
    //     uint24 fee;
    //     int24 tickLower;
    //     int24 tickUpper;
    //     uint256 amount0Desired;
    //     uint256 amount1Desired;
    //     uint256 amount0Min;
    //     uint256 amount1Min;
    //     address recipient;
    //     uint256 deadline;
    // }

    function test_comparePositionAndComputed() public {
        INonfungiblePositionManager.MintParams memory _param = INonfungiblePositionManager.MintParams(
            address(weth),
            address(usdc),
            500,
            lowerTick,
            upperTick,
            1 ether,
            1000 * 1e6,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = fungible.mint(_param);
        console2.log(amount0, amount1);

        // compute
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint256 amount0Computed, uint256 amount1Computed) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            liquidity
        );
        console2.log(amount0Computed, amount1Computed);
        console2.log(liquidity);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            amount0Computed,
            amount1Computed
        );
        console2.log(liquidity);

        (amount0, amount1) = pool.mint(address(this), lowerTick, upperTick, liquidity, "");
        console2.log(amount0, amount1);
    }

    function test_comparePositionAndComputed2() public {
        INonfungiblePositionManager.MintParams memory _param = INonfungiblePositionManager.MintParams(
            address(weth),
            address(usdc),
            500,
            lowerTick,
            upperTick,
            1 ether,
            1000 * 1e6,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = fungible.mint(_param);
        console2.log(amount0, amount1);

        // compute
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint256 amount0Computed, uint256 amount1Computed) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(lowerTick),
            TickMath.getSqrtRatioAtTick(upperTick),
            liquidity
        );
        console2.log(amount0Computed, amount1Computed);
        console2.log(liquidity);

        INonfungiblePositionManager.IncreaseLiquidityParams memory _increaseParam = INonfungiblePositionManager
            .IncreaseLiquidityParams(tokenId, amount0Computed, amount1Computed, 0, 0, block.timestamp + 1000);
        (liquidity, amount0, amount1) = fungible.increaseLiquidity(_increaseParam);
        console2.log(amount0, amount1);
        console2.log(liquidity);
    }

    function test_mintTwice() public {
        INonfungiblePositionManager.MintParams memory _param = INonfungiblePositionManager.MintParams(
            address(weth),
            address(usdc),
            500,
            lowerTick,
            upperTick,
            1 ether,
            1000 * 1e6,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = fungible.mint(_param);
        console2.log(tokenId, liquidity, amount0, amount1);

        _param = INonfungiblePositionManager.MintParams(
            address(weth),
            address(usdc),
            500,
            lowerTick,
            upperTick,
            1 ether,
            1000 * 1e6,
            0,
            0,
            address(this),
            block.timestamp + 1000
        );
        (tokenId, liquidity, amount0, amount1) = fungible.mint(_param);
        console2.log(tokenId, liquidity, amount0, amount1);
    }

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        if (msg.sender != address(pool)) {
            revert("Errors.ONLY_CALLBACK_CALLER");
        }

        if (amount0Owed > 0) {
            // if (amount0Owed > token0.balanceOf(address(this))) {
            //     console2.log("uniswapV3MintCallback amount0 > balance");
            //     console2.log(amount0Owed, token0.balanceOf(address(this)));
            // }
            weth.safeTransfer(msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            // if (amount1Owed > token1.balanceOf(address(this))) {
            //     console2.log("uniswapV3MintCallback amount1 > balance");
            //     console2.log(amount1Owed, token1.balanceOf(address(this)));
            // }
            usdc.safeTransfer(msg.sender, amount1Owed);
        }
    }
}
