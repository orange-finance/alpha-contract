// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IOrangeStrategyHelperV1 {
    function stoploss(int24 _inputTick) external;
}
