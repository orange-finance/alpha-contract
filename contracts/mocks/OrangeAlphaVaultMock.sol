// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeAlphaVault} from "../core/OrangeAlphaVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "forge-std/console2.sol";

contract OrangeAlphaVaultMock is OrangeAlphaVault {
    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        address _pool,
        address _aave,
        int24 _lowerTick,
        int24 _upperTick
    ) OrangeAlphaVault(_name, _symbol, _pool, _aave, _lowerTick, _upperTick) {}

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

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    // function getTicksByStorage() external view returns (Ticks memory) {
    //     return _getTicksByStorage();
    // }

    function checkSlippage(uint160 _currentSqrtRatioX96, bool _zeroForOne)
        external
        view
        returns (uint160 _swapThresholdPrice)
    {
        return _checkSlippage(_currentSqrtRatioX96, _zeroForOne);
    }

    function quoteEthPriceByTick(int24 _tick) external view returns (uint256) {
        return _quoteEthPriceByTick(_tick);
    }

    function computePercentageFromUpperRange(Ticks memory _ticks)
        external
        view
        returns (uint256 parcentageFromUpper_)
    {
        return _computePercentageFromUpperRange(_ticks);
    }

    /* ========== WRITE FUNCTIONS(EXTERNAL) ========== */

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    function swapAndAddLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        Ticks memory _ticks
    )
        external
        returns (
            uint128 liquidity_,
            uint256 amountDeposited0_,
            uint256 amountDeposited1_
        )
    {
        return _swapAndAddLiquidity(_amount0, _amount1, _ticks);
    }

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
