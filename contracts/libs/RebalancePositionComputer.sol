// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

//libraries
import {TickMath} from "../libs/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../libs/uniswap/OracleLibrary.sol";
import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";

uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

library RebalancePositionComputer {
    using TickMath for int24;
    using FullMath for uint256;

    /// @notice Compute the amount of collateral/debt to Aave and token0/token1 to Uniswap
    function computeRebalancePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio,
        address _token0,
        address _token1
    ) external pure returns (IOrangeAlphaVault.Positions memory) {
        if (_assets == 0) return IOrangeAlphaVault.Positions(0, 0, 0, 0);

        // compute ETH/USDC amount ration to add liquidity
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _currentTick.getSqrtRatioAtTick(),
            _lowerTick.getSqrtRatioAtTick(),
            _upperTick.getSqrtRatioAtTick(),
            1e18 //any amount
        );
        uint256 _amount0ValueInToken1 = OracleLibrary.getQuoteAtTick(_currentTick, uint128(_amount0), _token0, _token1);

        if (_hedgeRatio == 0) {
            uint256 _token1Balance = _assets.mulDiv(_amount1, (_amount0ValueInToken1 + _amount1));
            return IOrangeAlphaVault.Positions(0, 0, _token1Balance.mulDiv(_amount0, _amount1), _token1Balance);
        } else {
            IOrangeAlphaVault.Positions memory position_;

            //Collateral
            position_.collateralAmount1 = _computePositions(
                _assets,
                _amount1,
                _amount0ValueInToken1,
                _ltv,
                _hedgeRatio
            );

            uint256 _borrowUsdc = position_.collateralAmount1.mulDiv(_ltv, MAGIC_SCALE_1E8);
            //borrowing usdc amount to weth
            position_.debtAmount0 = OracleLibrary.getQuoteAtTick(_currentTick, uint128(_borrowUsdc), _token1, _token0);

            // amount added on Uniswap
            position_.token0Balance = position_.debtAmount0.mulDiv(MAGIC_SCALE_1E8, _hedgeRatio);
            position_.token1Balance = position_.token0Balance.mulDiv(_amount1, _amount0);
            return position_;
        }
    }

    function _computePositions(
        uint _assets,
        uint _amount1,
        uint _amount0ValueInToken1,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal pure returns (uint collateralAmount1) {
        //compute collateral/asset ratio
        uint256 _x = MAGIC_SCALE_1E8.mulDiv(_amount1, _amount0ValueInToken1);
        uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
            _ltv +
            MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
            MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio).mulDiv(_x, MAGIC_SCALE_1E8);
        collateralAmount1 = _assets.mulDiv(MAGIC_SCALE_1E8, _collateralRatioReciprocal);
    }

    ///@notice Get LTV by current and range prices
    ///@dev called by _computeRebalancePosition. maxLtv * (current price / upper price)
    function getLtvByRange(
        int24 _currentTick,
        int24 _upperTick,
        uint256 _maxLtv,
        address _token0,
        address _token1
    ) external pure returns (uint256 ltv_) {
        uint256 _currentPrice = quoteEthPriceByTick(_currentTick, _token0, _token1);
        uint256 _upperPrice = quoteEthPriceByTick(_upperTick, _token0, _token1);
        ltv_ = _maxLtv;
        if (_currentPrice < _upperPrice) {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
        }
    }

    ///@notice Quote eth price by USDC
    function quoteEthPriceByTick(int24 _tick, address _token0, address _token1) public pure returns (uint256) {
        return OracleLibrary.getQuoteAtTick(_tick, 1 ether, _token0, _token1);
    }
}
