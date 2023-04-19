// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeAlphaVault, IERC20, IVault, IFlashLoanRecipient} from "../core/OrangeAlphaVault.sol";
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";

// import "forge-std/console2.sol";

contract OrangeAlphaVaultMock is OrangeAlphaVault {
    // uint256 MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    int24 public avgTick;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        address _pool,
        address _token0,
        address _token1,
        address _router,
        address _aave,
        address _debtToken0,
        address _aToken1,
        address _params
    ) OrangeAlphaVault(_name, _symbol, _pool, _token0, _token1, _router, _aave, _debtToken0, _aToken1, _params) {}

    /* ========== ONLY MOCK FUNCTIONS ========== */

    function setTicks(int24 _lowerTick, int24 _upperTick) external {
        _validateTicks(_lowerTick, _upperTick);
        lowerTick = _lowerTick;
        upperTick = _upperTick;
    }

    function setAvgTick(int24 _avgTick) external {
        avgTick = _avgTick;
    }

    function getAavePoolLtv() external view returns (uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = aave.getUserAccountData(address(this));
        if (totalCollateralBase == 0) return 0;
        return FullMath.mulDiv(MAGIC_SCALE_1E8, totalDebtBase, totalCollateralBase);
    }

    function getLiquidity(int24 _lowerTick, int24 _upperTick) external view returns (uint128 liquidity_) {
        (liquidity_, , , , ) = pool.positions(_getPositionID(_lowerTick, _upperTick));
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    function alignTotalAsset(
        uint256 amount0Current,
        uint256 amount1Current,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) external view returns (uint256 totalAlignedAssets) {
        return _alignTotalAsset(_getTicksByStorage(), amount0Current, amount1Current, amount0Debt, amount1Supply);
    }

    function getLtvByRange(int24 _currentTick, int24 _upperTick) external view returns (uint256) {
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
        return _computeFeesEarned(isZero, feeGrowthInsideLast, liquidity, _getTicksByStorage());
    }

    function getPositionID() external view returns (bytes32 positionID) {
        Ticks memory _ticks = _getTicksByStorage();
        return _getPositionID(_ticks.lowerTick, _ticks.upperTick);
    }

    function getTicksByStorage() external view returns (Ticks memory) {
        return _getTicksByStorage();
    }

    function computeRebalancePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) external view returns (Positions memory position_) {
        return _computeRebalancePosition(_assets, _currentTick, _lowerTick, _upperTick, _ltv, _hedgeRatio);
    }

    function computeTargetPositionByShares(
        uint256 _debtAmount0,
        uint256 _collateralAmount1,
        uint256 _token0Balance,
        uint256 _token1Balance,
        uint256 _shares,
        uint256 _totalSupply
    ) external pure returns (Positions memory _position) {
        return
            _computeTargetPositionByShares(
                _debtAmount0,
                _collateralAmount1,
                _token0Balance,
                _token1Balance,
                _shares,
                _totalSupply
            );
    }

    function checkTickSlippage(int24 _currentTick, int24 _inputTick) external view {
        return _checkTickSlippage(_currentTick, _inputTick);
    }

    /* ========== WRITE FUNCTIONS(EXTERNAL) ========== */
    function depositLiquidityByShares(
        Balances memory _depositedBalances,
        uint256 _shares,
        uint256 _totalSupply,
        Ticks memory _ticks
    ) external {
        return _depositLiquidityByShares(_depositedBalances, _shares, _totalSupply, _ticks);
    }

    function addLiquidityInRebalance(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _targetAmount0,
        uint256 _targetAmount1
    ) external returns (uint128 targetLiquidity_) {
        return _addLiquidityInRebalance(_lowerTick, _upperTick, _targetAmount0, _targetAmount1);
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    function burnAndCollectFees(int24 _lowerTick, int24 _upperTick) external returns (uint256 burn0_, uint256 burn1_) {
        (uint128 _liquidity, , , , ) = pool.positions(_getPositionID(_lowerTick, _upperTick));

        return _burnAndCollectFees(_lowerTick, _upperTick, _liquidity);
    }

    function swapAmountOut(bool _zeroForOne, uint256 _amountOut) external returns (uint256 amountIn_) {
        return _swapAmountOut(_zeroForOne, _amountOut);
    }

    function swapAmountIn(bool _zeroForOne, uint256 _amountIn) external returns (uint256 amountOut_) {
        return _swapAmountIn(_zeroForOne, _amountIn);
    }

    function validateTicks(int24 _lowerTick, int24 _upperTick) external view {
        _validateTicks(_lowerTick, _upperTick);
    }

    /* ========== CALLBACK FUNCTIONS ========== */
}
