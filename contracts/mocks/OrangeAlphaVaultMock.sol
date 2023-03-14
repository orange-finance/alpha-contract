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

    function setAvgTick(int24 _avgTick) external {
        avgTick = _avgTick;
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    function alignTotalAsset(
        uint256 amount0Current,
        uint256 amount1Current,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) external view returns (uint256 totalAlignedAssets) {
        return
            _alignTotalAsset(
                _getTicksByStorage(),
                amount0Current,
                amount1Current,
                amount0Debt,
                amount1Supply
            );
    }

    function getLtvByRange(
        int24 _currentTick,
        int24 _upperTick
    ) external view returns (uint256) {
        return _getLtvByRange(_currentTick, _upperTick);
    }

    function quoteEthPriceByTick(int24 _tick) external view returns (uint256) {
        return _quoteEthPriceByTick(_tick);
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

    function getPositionID() external view returns (bytes32 positionID) {
        Ticks memory _ticks = _getTicksByStorage();
        return _getPositionID(_ticks.lowerTick, _ticks.upperTick);
    }

    function getTicksByStorage() external view returns (Ticks memory) {
        return _getTicksByStorage();
    }

    function computePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) external view returns (Position memory position_) {
        return
            _computePosition(
                _assets,
                _currentTick,
                _lowerTick,
                _upperTick,
                _ltv,
                _hedgeRatio
            );
    }

    function computeHedgeAndLiquidityByShares(
        uint256 _shares,
        Ticks memory _ticks
    )
        external
        view
        returns (
            uint256 _targetDebtAmount0,
            uint256 _targetCollateralAmount1,
            uint128 _targetLiquidity
        )
    {
        return _computeHedgeAndLiquidityByShares(_shares, _ticks);
    }

    function checkTickSlippage(
        int24 _currentTick,
        int24 _inputTick
    ) external view {
        return _checkTickSlippage(_currentTick, _inputTick);
    }

    /* ========== WRITE FUNCTIONS(EXTERNAL) ========== */

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    function burnShare(
        uint256 _shares,
        uint256 _totalSupply,
        Ticks memory _ticks
    ) external returns (uint256 burnAndFees0_, uint256 burnAndFees1_) {
        return _burnShare(_shares, _totalSupply, _ticks);
    }

    function burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick
    )
        external
        returns (uint256 burn0_, uint256 burn1_, uint256 fee0_, uint256 fee1_)
    {
        (uint128 _liquidity, , , , ) = pool.positions(
            _getPositionID(_lowerTick, _upperTick)
        );

        return _burnAndCollectFees(_lowerTick, _upperTick, _liquidity);
    }

    function swapSurplusAmount(
        Balances memory _balances,
        uint128 _targetLiquidity,
        Ticks memory _ticks
    ) external {
        return _swapSurplusAmount(_balances, _targetLiquidity, _ticks);
    }

    function validateTicks(int24 _lowerTick, int24 _upperTick) external view {
        _validateTicks(_lowerTick, _upperTick);
    }

    /* ========== CALLBACK FUNCTIONS ========== */
}
