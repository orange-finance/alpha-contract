// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

library Errors {
    string public constant TICKS = "Ticks";
    string public constant DEPOSIT_RECEIVER = "Receiver";
    string public constant DEPOSIT_STOPLOSSED = "DepositStoplossed";
    string public constant CAPOVER = "CapOver";
    string public constant ZERO = "Zero";
    string public constant ADD_LIQUIDITY_AMOUNTS = "LiquidityAmounts";
    string public constant PARAMS = "Params";
    string public constant INCORRECT_LENGTH = "Length";
    string public constant HIGH_SLIPPAGE = "Slippage";
    string public constant CALLBACK_CALLER = "Callback";
    string public constant WHEN_CAN_STOPLOSS = "Stoploss";
    string public constant LESS = "Less";
    string public constant AAVE_MISMATCH = "Aave";
    string public constant LOCKUP = "Lockup";
    string public constant REBALANCER = "Rebalancer";
    string public constant MORE = "More";
    string public constant INITIAL_DEPOSIT = "InitialDeposit";
    string public constant NOT_INITIAL_DEPOSIT = "NotInitialDeposit";
    string public constant SURPLUS_ZERO = "SurplusZero";
}
