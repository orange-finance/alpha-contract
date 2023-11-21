// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {IUniswapV3SingleTickLiquidityHandler} from "@src/vendor/dopexV2/IUniswapV3SingleTickLiquidityHandler.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FixedPoint128} from "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";
import {FullMath} from "@src/libs/uniswap/FullMath.sol";
import {TickMath} from "@src/libs/uniswap/TickMath.sol";
import {LiquidityAmounts} from "@src/libs/uniswap/LiquidityAmounts.sol";

library DopexUniV3HandlerLib {
    function positionId(
        IUniswapV3SingleTickLiquidityHandler,
        IUniswapV3Pool _pool,
        int24 lowerTick,
        int24 upperTick
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_pool, lowerTick, upperTick)));
    }

    function getTotalSingleTickLiquidity(
        IUniswapV3SingleTickLiquidityHandler handler,
        IUniswapV3Pool _pool,
        int24 tick,
        int24 spacing
    ) internal view returns (uint128) {
        uint256 _pid = positionId(handler, _pool, tick, tick + spacing);
        uint256 _share = handler.balanceOf(address(this), _pid);

        return handler.convertToAssets(_share, _pid);
    }

    function getTotalSingleTickShares(
        IUniswapV3SingleTickLiquidityHandler handler,
        IUniswapV3Pool _pool,
        int24 tick,
        int24 spacing
    ) internal view returns (uint256) {
        uint256 _pid = positionId(handler, _pool, tick, tick + spacing);
        return handler.balanceOf(address(this), _pid);
    }

    function getSingleTickShares(
        IUniswapV3SingleTickLiquidityHandler handler,
        IUniswapV3Pool _pool,
        int24 tick,
        int24 spacing,
        uint128 liquidity
    ) internal view returns (uint256) {
        uint256 _pid = positionId(handler, _pool, tick, tick + spacing);
        return handler.convertToShares(liquidity, _pid);
    }

    // TODO: skip current tick
    function getLiquidityAverageInRange(
        IUniswapV3SingleTickLiquidityHandler handler,
        IUniswapV3Pool _pool,
        int24 lowerTick,
        int24 upperTick,
        // int24 currentTick,
        int24 tickSpacing
    ) internal view returns (uint128 liquidity) {
        int24 _spacing = tickSpacing;

        int24 _t = lowerTick;
        uint256 _pos = 0;

        for (int24 _nt = _t + tickSpacing; _nt < upperTick; ) {
            liquidity += getTotalSingleTickLiquidity(handler, _pool, _t, _spacing);

            unchecked {
                _t = _nt;
                _nt += _spacing;
                _pos++;
            }
        }

        liquidity /= uint128(uint24((upperTick - lowerTick) / _spacing));
    }

    // function getAmountsForLiquidity(
    //     IUniswapV3SingleTickLiquidityHandler,
    //     IUniswapV3Pool pool,
    //     int24 lowerTick,
    //     int24 upperTick,
    //     int24 currentTick,
    //     int24 tickSpacing,
    //     uint128 liquidity
    // ) internal view returns (uint256 amount0, uint256 amount1) {
    //     int24 _t = lowerTick;
    //     (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

    //     for (int24 _nt = _t + tickSpacing; _nt < upperTick; ) {
    //         if (_nt - currentTick > tickSpacing) {
    //             (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
    //                 _sqrtRatioX96,
    //                 TickMath.getSqrtRatioAtTick(_t),
    //                 TickMath.getSqrtRatioAtTick(_nt),
    //                 liquidity
    //             );

    //             amount0 += _amount0;
    //             amount1 += _amount1;
    //         }

    //         unchecked {
    //             _t = _nt;
    //             _nt += tickSpacing;
    //         }
    //     }
    // }

    function getFeesEarned(
        IUniswapV3SingleTickLiquidityHandler handler,
        IUniswapV3Pool pool,
        int24 lowerTick,
        int24 upperTick
    ) public view returns (uint256 fee0, uint256 fee1) {
        IUniswapV3SingleTickLiquidityHandler _handler = handler;
        uint256 _tid = _handler.getHandlerIdentifier(abi.encode(pool, lowerTick, upperTick));
        IUniswapV3SingleTickLiquidityHandler.TokenIdInfo memory _ti = _handler.tokenIds(_tid);

        (uint128 _tokensOwed0, uint128 _tokensOwed1) = getAllFeeOwed(handler, pool, lowerTick, upperTick);

        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        uint128 _uLiqTotal = _handler.convertToAssets(_handler.balanceOf(address(this), _tid), _tid);

        uint160 _sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(lowerTick);
        uint160 _sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(upperTick);

        (uint256 _uLiq0, uint256 _uLiq1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            _sqrtRatioAX96,
            _sqrtRatioBX96,
            _uLiqTotal
        );

        (uint256 _total0, uint256 _total1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            _sqrtRatioAX96,
            _sqrtRatioBX96,
            _ti.totalLiquidity
        );

        fee0 = (_tokensOwed0 * _uLiq0) / _total0;
        fee1 = (_tokensOwed1 * _uLiq1) / _total1;
    }

    function getAllFeeOwed(
        IUniswapV3SingleTickLiquidityHandler handler,
        IUniswapV3Pool pool,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint128, uint128) {
        uint256 _tid = handler.getHandlerIdentifier(abi.encode(pool, lowerTick, upperTick));
        IUniswapV3SingleTickLiquidityHandler.TokenIdInfo memory _ti = handler.tokenIds(_tid);

        uint128 _totalLiquidity = _ti.totalLiquidity;
        uint128 _liquidityUsed = _ti.liquidityUsed;

        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 _tokensOwed0,
            uint128 _tokensOwed1
        ) = pool.positions(keccak256(abi.encode(address(handler), lowerTick, upperTick)));

        unchecked {
            _tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - _ti.feeGrowthInside0LastX128,
                    _totalLiquidity - _liquidityUsed,
                    FixedPoint128.Q128
                )
            );
            _tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - _ti.feeGrowthInside1LastX128,
                    _totalLiquidity - _liquidityUsed,
                    FixedPoint128.Q128
                )
            );
        }

        return (_tokensOwed0, _tokensOwed1);
    }

    function getFeeGrowths(
        IUniswapV3SingleTickLiquidityHandler handler,
        IUniswapV3Pool pool,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns (uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) {
        (, feeGrowthInside0LastX128, feeGrowthInside1LastX128, , ) = pool.positions(
            keccak256(abi.encode(address(handler), lowerTick, upperTick))
        );
    }
}
