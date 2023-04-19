// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.16;

library Errors {
    //OrangeAlphaVault
    string public constant ONLY_PERIPHERY = "101";
    string public constant ONLY_STRATEGISTS_OR_GELATO = "102";
    string public constant ONLY_STRATEGISTS = "103";
    string public constant ONLY_CALLBACK_CALLER = "104";
    string public constant INVALID_TICKS = "105";
    string public constant INVALID_AMOUNT = "106";
    string public constant INVALID_DEPOSIT_AMOUNT = "107";
    string public constant SURPLUS_ZERO = "108";
    string public constant LESS_AMOUNT = "109";
    string public constant LESS_LIQUIDITY = "110";
    string public constant HIGH_SLIPPAGE = "111";
    string public constant EQUAL_COLLATERAL_OR_DEBT = "112";
    string public constant NO_NEED_FLASH = "113";
    string public constant ONLY_BALANCER_VAULT = "114";
    string public constant INVALID_FLASHLOAN_HASH = "115";
    string public constant FLASHLOAN_LACK_OF_BALANCE = "116";
    string public constant INVALID_SHARES = "117";

    //OrangeAlphaPeriphery
    string public constant MERKLE_ALLOWLISTED = "201";
    string public constant CAPOVER = "202";
    string public constant LOCKUP = "203";
    //OrangeAlphaParameters
    string public constant INVALID_PARAM = "301";
}
