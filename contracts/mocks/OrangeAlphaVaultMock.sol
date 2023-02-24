// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeAlphaVault} from "../core/OrangeAlphaVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FullMath} from "../vendor/uniswap/LiquidityAmounts.sol";

// import "forge-std/console2.sol";

contract OrangeAlphaVaultMock is OrangeAlphaVault {
    // uint256 MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    int24 public avgTick;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 __decimal,
        address _pool,
        address _token0,
        address _token1,
        address _aave,
        address _debtToken0,
        address _aToken1,
        address _params
    )
        OrangeAlphaVault(
            _name,
            _symbol,
            __decimal,
            _pool,
            _token0,
            _token1,
            _aave,
            _debtToken0,
            _aToken1,
            _params
        )
    {}

    /* ========== ONLY MOCK FUNCTIONS ========== */

    function setAaveTokens(address _debtToken0, address _aToken1) external {
        debtToken0 = IERC20(_debtToken0);
        aToken1 = IERC20(_aToken1);
    }

    function setTicks(int24 _lowerTick, int24 _upperTick) external {
        _validateTicks(_lowerTick, _upperTick);
        lowerTick = _lowerTick;
        upperTick = _upperTick;
    }

    function setStoplossed(bool _stoplossed) external {
        stoplossed = _stoplossed;
    }

    function getAavePoolLtv() external view returns (uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = aave
            .getUserAccountData(address(this));
        if (totalCollateralBase == 0) return 0;
        return
            FullMath.mulDiv(
                MAGIC_SCALE_1E8,
                totalDebtBase,
                totalCollateralBase
            );
    }

    // function setDeposits(address _user, uint256 _amount) external {
    //     deposits[_user].assets = _amount;
    // }

    // function setTotalDeposits(uint256 _amount) external {
    //     totalDeposits = _amount;
    // }

    // function getTwap() external view returns (int24) {
    //     return _getTwap();
    // }

    function setAvgTick(int24 _avgTick) external {
        avgTick = _avgTick;
    }

    // function _getTwap() internal view override returns (int24) {
    //     if (avgTick == 0) {
    //         return super._getTwap();
    //     } else {
    //         return avgTick;
    //     }
    // }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    function getLtvByRange() external view returns (uint256) {
        return
            _getLtvByRange(
                _getTicksByStorage().currentTick,
                stoplossLowerTick,
                stoplossUpperTick
            );
    }

    function checkSlippage(uint160 _currentSqrtRatioX96, bool _zeroForOne)
        external
        view
        returns (uint160 _swapThresholdPrice)
    {
        return _setSlippage(_currentSqrtRatioX96, _zeroForOne);
    }

    function quoteEthPriceByTick(int24 _tick) external view returns (uint256) {
        return _quoteEthPriceByTick(_tick);
    }

    // function computePercentageFromUpperRange(Ticks memory _ticks)
    //     external
    //     view
    //     returns (uint256 parcentageFromUpper_)
    // {
    //     return _computePercentageFromUpperRange(_ticks);
    // }

    function alignTotalAsset(
        UnderlyingAssets memory _underlyingAssets,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) external view returns (uint256 totalAlignedAssets) {
        return
            _alignTotalAsset(
                _getTicksByStorage(),
                _underlyingAssets,
                amount0Debt,
                amount1Supply
            );
    }

    function computeFeesEarned(
        bool isZero,
        uint256 feeGrowthInsideLast,
        uint128 liquidity
    ) external view returns (uint256 fee) {
        return
            _computeFeesEarned(
                isZero,
                feeGrowthInsideLast,
                liquidity,
                _getTicksByStorage()
            );
    }

    function canStoploss() external view returns (bool) {
        return
            _canStoploss(
                _getTicksByStorage().currentTick,
                stoplossLowerTick,
                stoplossUpperTick
            );
    }

    function getPositionID() external view returns (bytes32 positionID) {
        Ticks memory _ticks = _getTicksByStorage();
        return _getPositionID(_ticks.lowerTick, _ticks.upperTick);
    }

    function getTicksByStorage() external view returns (Ticks memory) {
        return _getTicksByStorage();
    }

    function computeSupplyAndBorrow(uint256 _assets)
        external
        view
        returns (uint256 supply_, uint256 borrow_)
    {
        Ticks memory _ticks = _getTicksByStorage();
        return
            _computeSupplyAndBorrow(
                _assets,
                _ticks.currentTick,
                _ticks.lowerTick,
                _ticks.upperTick
            );
    }

    // function computeSwapAmount(uint256 _amount0, uint256 _amount1)
    //     external
    //     view
    //     returns (bool _zeroForOne, int256 _swapAmount)
    // {
    //     Ticks memory _ticks = _getTicksByStorage();
    //     return _computeSwapAmount(_amount0, _amount1, _ticks);
    // }

    /* ========== WRITE FUNCTIONS(EXTERNAL) ========== */

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    // function swapAndAddLiquidity(
    //     uint256 _amount0,
    //     uint256 _amount1,
    //     Ticks memory _ticks
    // )
    //     external
    //     returns (
    //         uint128 liquidity_,
    //         uint256 amountDeposited0_,
    //         uint256 amountDeposited1_
    //     )
    // {
    //     return _swapAndAddLiquidity(_amount0, _amount1, _ticks);
    // }

    function burnShare(
        uint256 _shares,
        uint256 _totalSupply,
        Ticks memory _ticks
    )
        external
        returns (
            uint256 burnAndFees0_,
            uint256 burnAndFees1_,
            uint128 liquidityBurned_
        )
    {
        return _burnShare(_shares, _totalSupply, _ticks);
    }

    function burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    )
        external
        returns (
            uint256 burn0_,
            uint256 burn1_,
            uint256 fee0_,
            uint256 fee1_,
            uint256 preBalance0_,
            uint256 preBalance1_
        )
    {
        return _burnAndCollectFees(_lowerTick, _upperTick, _liquidity);
    }

    function validateTicks(int24 _lowerTick, int24 _upperTick) external view {
        _validateTicks(_lowerTick, _upperTick);
    }

    /* ========== CALLBACK FUNCTIONS ========== */
}
