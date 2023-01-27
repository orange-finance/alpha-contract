// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {TickMath} from "../vendor/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "../vendor/uniswap/LiquidityAmounts.sol";

contract UniswapV3PoolAccessorMock is
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback
{
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;

    IUniswapV3Pool public pool;

    IERC20 public token0; //weth
    IERC20 public token1; //usdc

    /* ========== CONSTRUCTOR ========== */
    constructor(address _pool) {
        // setting adresses and approving
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(pool.token0());
        token1 = IERC20(pool.token1());
    }

    /* ========== VIWE FUNCTIONS ========== */
    function getSqrtRatioX96() external view returns (uint160) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        return _sqrtRatioX96;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function mint(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _amount0,
        uint256 _amount1
    ) external {
        token0.safeTransferFrom(msg.sender, address(this), _amount0);
        token1.safeTransferFrom(msg.sender, address(this), _amount1);

        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        uint128 liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtRatioX96,
            _lowerTick.getSqrtRatioAtTick(),
            _upperTick.getSqrtRatioAtTick(),
            _amount0,
            _amount1
        );
        pool.mint(msg.sender, _lowerTick, _upperTick, liquidity_, "");
    }

    function swap(
        bool _zeroForOne,
        uint256 _amount,
        uint160 _sqrtPriceLimitX96
    ) external {
        if (_zeroForOne) {
            token0.safeTransferFrom(msg.sender, address(this), _amount);
        } else {
            token1.safeTransferFrom(msg.sender, address(this), _amount);
        }

        pool.swap(
            msg.sender,
            _zeroForOne, //token1 to token0
            SafeCast.toInt256(_amount),
            _sqrtPriceLimitX96,
            ""
        );
    }

    function burn(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    ) external {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                _sqrtRatioX96,
                _lowerTick.getSqrtRatioAtTick(),
                _upperTick.getSqrtRatioAtTick(),
                _liquidity
            );
        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);

        pool.burn(_lowerTick, _upperTick, _liquidity);
    }

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        if (msg.sender != address(pool)) {
            revert("CallbackCaller");
        }

        if (amount0Owed > 0) {
            token0.safeTransfer(msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            token1.safeTransfer(msg.sender, amount1Owed);
        }
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external override {
        if (msg.sender != address(pool)) {
            revert("CallbackCaller");
        }

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
