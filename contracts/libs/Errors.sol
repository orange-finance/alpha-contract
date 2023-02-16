// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

library Errors {
    string public constant TICKS = "1";
    string public constant DEPOSIT_RECEIVER = "2";
    string public constant DEPOSIT_STOPLOSSED = "3";
    string public constant CAPOVER = "4";
    string public constant ZERO = "5";
    string public constant ADD_LIQUIDITY_AMOUNTS = "6";
    string public constant PARAMS = "7";
    string public constant INCORRECT_LENGTH = "8";
    string public constant HIGH_SLIPPAGE = "9";
    string public constant CALLBACK_CALLER = "10";
    string public constant WHEN_CAN_STOPLOSS = "11";
    string public constant LESS = "12";
    string public constant AAVE_MISMATCH = "13";
    string public constant LOCKUP = "14";
    string public constant REBALANCER = "15";
    string public constant MORE = "16";
    string public constant NOT_DEDICATED_MSG_SENDER = "17";
    string public constant MERKLE_ALLOW_LIST = "18";
    // string public constant ERC20_MINT_ZERO = "20";
    // string public constant ERC20_BURN_ZERO_ADDRESS = "21";
    // string public constant ERC20_BURN_EXCEED_BALANCE = "22";
    // string public constant ERC20_APPROVE_ZERO = "23";
    // string public constant ERC20_INSUFFICIENT_ALLOWANCE = "24";
}
