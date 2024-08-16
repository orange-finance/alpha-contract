// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeStrategyImplV1Initializable} from "@src/coreV1/proxy/OrangeStrategyImplV1Initializable.sol";

contract OrangeStrategyImplV1Harness is OrangeStrategyImplV1Initializable {
    function checkTickSlippage(int24 _currentTick, int24 _inputTick) external view {
        return _checkTickSlippage(_currentTick, _inputTick);
    }

    /* ========== WRITE FUNCTIONS(EXTERNAL) ========== */
    function addLiquidityInRebalance(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _targetAmount0,
        uint256 _targetAmount1
    ) external returns (uint128 targetLiquidity_) {
        return _addLiquidityInRebalance(_lowerTick, _upperTick, _targetAmount0, _targetAmount1);
    }
}
