// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeLiquidityPool} from "../interfaces/IOrangeLiquidityPool.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TickMath} from "../libs/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "../libs/uniswap/LiquidityAmounts.sol";

import "forge-std/console2.sol";

contract OrangeLiquidityPool is IOrangeLiquidityPool, IUniswapV3MintCallback {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;

    /* ========== Structs ========== */

    /* ========== CONSTANTS ========== */
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== STORAGES ========== */

    /* ========== PARAMETERS ========== */
    IUniswapV3Pool public immutable pool;
    // IERC20 public immutable token0;
    // IERC20 public immutable token1;
    uint24 public immutable fee;

    /* ========== MODIFIER ========== */

    /* ========== CONSTRUCTOR ========== */
    constructor(address _pool) {
        pool = IUniswapV3Pool(_pool);
        fee = pool.fee();
        // token0.safeApprove(_pool, type(uint256).max);
        // token1.safeApprove(_pool, type(uint256).max);
    }

    function getCurrentLiquidity(int24 _lowerTick, int24 _upperTick) external view returns (uint128 liquidity_) {
        (liquidity_, , , , ) = pool.positions(keccak256(abi.encodePacked(address(this), _lowerTick, _upperTick)));
    }

    function getAmountsForLiquidity(ParamsOfLiquidity calldata _params) external view returns (uint256, uint256) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            _params.lowerTick.getSqrtRatioAtTick(),
            _params.upperTick.getSqrtRatioAtTick(),
            _params.liquidity
        );
        return (_params.token0 < _params.token1) ? (amount0, amount1) : (amount1, amount0);
    }

    function getLiquidityForAmounts(ParamsOfAmount calldata _params) external view returns (uint128 liquidity) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint _amount0, uint _amount1) = (_params.token0 < _params.token1)
            ? (_params.amount0, _params.amount1)
            : (_params.amount1, _params.amount0);

        return
            LiquidityAmounts.getLiquidityForAmounts(
                _sqrtRatioX96,
                _params.lowerTick.getSqrtRatioAtTick(),
                _params.upperTick.getSqrtRatioAtTick(),
                _amount0,
                _amount1
            );
    }

    function getFeesEarned(Params calldata _params) external view returns (uint256, uint256) {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(keccak256(abi.encodePacked(address(this), _params.lowerTick, _params.upperTick)));
        uint _fee0 = _computeFeesEarned(
            pool.token0(),
            feeGrowthInside0Last,
            liquidity,
            _params.lowerTick,
            _params.upperTick
        ) + uint256(tokensOwed0);
        uint _fee1 = _computeFeesEarned(
            pool.token1(),
            feeGrowthInside1Last,
            liquidity,
            _params.lowerTick,
            _params.upperTick
        ) + uint256(tokensOwed1);

        return (_params.token0 < _params.token1) ? (_fee0, _fee1) : (_fee1, _fee0);
    }

    ///@notice Compute one of fee amount
    ///@dev similar to Arrakis'
    function _computeFeesEarned(
        address token,
        uint256 feeGrowthInsideLast,
        uint128 liquidity,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (uint256 fee_) {
        (, int24 _tick, , , , , ) = pool.slot0();

        //TODO
        bool isZero = (token == pool.token0()) ? true : false;

        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(_lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(_upperTick);
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(_lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(_upperTick);
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (_tick >= _lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (_tick < _upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;
            fee_ = uint256(liquidity).mulDiv(
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    /* ========== WRITE FUNCTIONS ========== */

    function mint(MintParams calldata _params) external returns (uint256, uint256) {
        bytes memory data = abi.encode(_params.receiver);
        console2.log(msg.sender, "msg.sender");
        console2.log(_params.receiver, "_params.receiver");

        (uint256 amount0, uint256 amount1) = pool.mint(
            address(this),
            _params.lowerTick,
            _params.upperTick,
            _params.liquidity,
            data
        );
        return (_params.token0 < _params.token1) ? (amount0, amount1) : (amount1, amount0);
    }

    function collect(Params calldata _params) external returns (uint128, uint128) {
        (uint128 _amount0, uint128 _amount1) = pool.collect(
            msg.sender,
            _params.lowerTick,
            _params.upperTick,
            type(uint128).max,
            type(uint128).max
        );
        return (_params.token0 < _params.token1) ? (_amount0, _amount1) : (_amount1, _amount0);
    }

    function burn(ParamsOfLiquidity calldata _params) external returns (uint256, uint256) {
        (uint _burn0, uint _burn1) = pool.burn(_params.lowerTick, _params.upperTick, _params.liquidity);
        return (_params.token0 < _params.token1) ? (_burn0, _burn1) : (_burn1, _burn0);
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata _data) external override {
        console2.log("callback start");
        if (msg.sender != address(pool)) {
            revert("Errors.ONLY_CALLBACK_CALLER");
        }
        address sender = abi.decode(_data, (address));
        console2.log(sender, "callback sender");
        console2.log(msg.sender, "callback msg.sender");

        if (amount0Owed > 0) {
            if (amount0Owed > IERC20(pool.token0()).balanceOf(sender)) {
                console2.log("uniswapV3MintCallback amount0 > balance");
                console2.log(amount0Owed, IERC20(pool.token0()).balanceOf(sender));
            }
            IERC20(pool.token0()).safeTransferFrom(sender, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            if (amount1Owed > IERC20(pool.token1()).balanceOf(sender)) {
                console2.log("uniswapV3MintCallback amount1 > balance");
                console2.log(amount1Owed, IERC20(pool.token1()).balanceOf(sender));
            }
            IERC20(pool.token1()).safeTransferFrom(sender, msg.sender, amount1Owed);
        }
    }
}
