// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeStrategyHelperV1} from "./OrangeStrategyHelperV1.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";

//libraries
import {UniswapV3Twap, IUniswapV3Pool} from "../libs/UniswapV3Twap.sol";
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";
import {TickMath} from "../libs/uniswap/TickMath.sol";

contract OrangeStrategyHelperV1Next is OrangeStrategyHelperV1 {
    using UniswapV3Twap for IUniswapV3Pool;
    using FullMath for uint256;

    /* ========== STORAGE ========== */
    int24 public nextUnderLowerTick;
    int24 public nextUnderUpperTick;
    int24 public nextOverLowerTick;
    int24 public nextOverUpperTick;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault) OrangeStrategyHelperV1(_vault) {}

    /* ========== VIEW FUNCTIONS ========== */
    function checker() external view override returns (bool, bytes memory) {
        if (vault.hasPosition()) {
            int24 _currentTick = ILiquidityPoolManager(liquidityPool).getCurrentTick();
            int24 _twap = ILiquidityPoolManager(liquidityPool).getTwap(5 minutes);

            //if current tick and twap is under stoploss range
            if (_currentTick < stoplossLowerTick && _twap < stoplossLowerTick) {
                bytes memory execPayload = abi.encodeWithSelector(
                    OrangeStrategyHelperV1.rebalance.selector,
                    nextUnderLowerTick,
                    nextUnderUpperTick,
                    TickMath.MIN_TICK,
                    TickMath.MAX_TICK,
                    0,
                    0
                );
                return (true, execPayload);
            } else if (_currentTick > stoplossUpperTick && _twap > stoplossUpperTick) {
                //over
                bytes memory execPayload = abi.encodeWithSelector(
                    OrangeStrategyHelperV1.rebalance.selector,
                    nextOverLowerTick,
                    nextOverUpperTick,
                    TickMath.MIN_TICK,
                    TickMath.MAX_TICK,
                    0,
                    0
                );
                return (true, execPayload);
            }
        }
        return (false, bytes("ERROR_CANNOT_REBALANCE"));
    }

    function setNextTick(
        int24 _stoplossLowerTick,
        int24 _stoplossUpperTick,
        int24 _nextUnderLowerTick,
        int24 _nextUnderUpperTick,
        int24 _nextOverLowerTick,
        int24 _nextOverUpperTick
    ) external onlyStrategist {
        stoplossLowerTick = _stoplossLowerTick;
        stoplossUpperTick = _stoplossUpperTick;
        nextUnderLowerTick = _nextUnderLowerTick;
        nextUnderUpperTick = _nextUnderUpperTick;
        nextOverLowerTick = _nextOverLowerTick;
        nextOverUpperTick = _nextOverUpperTick;
    }
}
