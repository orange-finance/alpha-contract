// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeAlphaVault, FullMath, LiquidityAmounts, OracleLibrary, IOrangeAlphaVault, TickMath} from "../core/OrangeAlphaVault.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaPeriphery.sol";
import {IUniswapV3Pool} from "../libs/UniswapV3Twap.sol";
import {RebalancePositionComputer} from "../libs/RebalancePositionComputer.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaComputer {
    using TickMath for int24;
    using FullMath for uint256;
    // using Ints for int24;

    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    // uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== PARAMETERS ========== */
    OrangeAlphaVault public vault;
    IOrangeAlphaParameters public params;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault, address _params) {
        vault = OrangeAlphaVault(_vault);
        params = IOrangeAlphaParameters(_params);
    }

    /// @notice Compute the amount of collateral/debt to Aave and token0/token1 to Uniswap
    function computeApplyHedgeRatio(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _targetHedgeRatio
    ) external view returns (uint256) {
        uint _maxHedgeRatio = computeMaxHedgeRatio(_lowerTick, _upperTick);
        return (_targetHedgeRatio > _maxHedgeRatio) ? _maxHedgeRatio : _targetHedgeRatio;
    }

    /// @notice Compute the amount of collateral/debt to Aave and token0/token1 to Uniswap
    function computeMaxHedgeRatio(int24 _lowerTick, int24 _upperTick) public view returns (uint256 maxHedgeRatio_) {
        IUniswapV3Pool _pool = vault.pool();
        (, int24 _currentTick, , , , , ) = _pool.slot0();

        // compute ETH/USDC amount ration to add liquidity
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _currentTick.getSqrtRatioAtTick(),
            _lowerTick.getSqrtRatioAtTick(),
            _upperTick.getSqrtRatioAtTick(),
            1e18 //any amount
        );
        uint256 _amount0ValueInToken1 = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_amount0),
            address(vault.token0()),
            address(vault.token1())
        );

        return MAGIC_SCALE_1E8.mulDiv(_amount1, _amount0ValueInToken1) + MAGIC_SCALE_1E8;
    }

    /// @notice Compute the amount of collateral/debt to Aave and token0/token1 to Uniswap
    function computeRebalancePosition(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) public view returns (IOrangeAlphaVault.Positions memory) {
        IUniswapV3Pool _pool = vault.pool();
        (, int24 _currentTick, , , , , ) = _pool.slot0();
        uint _assets = vault.totalAssets();

        if (_assets == 0) return IOrangeAlphaVault.Positions(0, 0, 0, 0);

        return
            RebalancePositionComputer.computeRebalancePosition(
                _assets,
                _currentTick,
                _lowerTick,
                _upperTick,
                _ltv,
                _hedgeRatio,
                address(vault.token0()),
                address(vault.token1())
            );
    }

    ///@notice Get LTV by current and range prices
    ///@dev called by _computeRebalancePosition. maxLtv * (current price / upper price)
    function getLtvByRange(int24 _upperTick) public view returns (uint256 ltv_) {
        IUniswapV3Pool _pool = vault.pool();
        (, int24 _currentTick, , , , , ) = _pool.slot0();

        return
            RebalancePositionComputer.getLtvByRange(
                _currentTick,
                _upperTick,
                params.maxLtv(),
                address(vault.token0()),
                address(vault.token1())
            );
    }
}
