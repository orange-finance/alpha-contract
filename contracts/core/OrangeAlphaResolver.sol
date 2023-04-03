// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";
import {IResolver} from "../interfaces/IResolver.sol";
import {UniswapV3Twap, IUniswapV3Pool} from "../libs/UniswapV3Twap.sol";
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";

// import "forge-std/console2.sol";

contract OrangeAlphaResolver is IResolver {
    using UniswapV3Twap for IUniswapV3Pool;
    using FullMath for uint256;
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== ERRORS ========== */
    string constant ERROR_CANNOT_STOPLOSS = "CANNOT_STOPLOSS";

    /* ========== PARAMETERS ========== */
    IOrangeAlphaVault public vault;
    IOrangeAlphaParameters public params;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault, address _params) {
        vault = IOrangeAlphaVault(_vault);
        params = IOrangeAlphaParameters(_params);
    }

    // @inheritdoc IResolver
    function checker() external view override returns (bool, bytes memory) {
        if (vault.hasPosition()) {
            IUniswapV3Pool _pool = vault.pool();
            (, int24 _currentTick, , , , , ) = _pool.slot0();
            int24 _twap = _pool.getTwap();
            int24 _stoplossLowerTick = vault.stoplossLowerTick();
            int24 _stoplossUpperTick = vault.stoplossUpperTick();
            if (
                _isOutOfRange(_currentTick, _stoplossLowerTick, _stoplossUpperTick) &&
                _isOutOfRange(_twap, _stoplossLowerTick, _stoplossUpperTick)
            ) {
                uint256 _minFinalBalance = vault.totalAssets().mulDiv(
                    MAGIC_SCALE_1E4 - params.slippageBPS(),
                    MAGIC_SCALE_1E4
                );
                bytes memory execPayload = abi.encodeWithSelector(
                    IOrangeAlphaVault.stoploss.selector,
                    _twap,
                    _minFinalBalance
                );
                return (true, execPayload);
            }
        }
        return (false, bytes(ERROR_CANNOT_STOPLOSS));
    }

    ///@notice Can stoploss when has position and out of range
    function _isOutOfRange(int24 _targetTick, int24 _lowerTick, int24 _upperTick) internal pure returns (bool) {
        return (_targetTick > _upperTick || _targetTick < _lowerTick);
    }
}
