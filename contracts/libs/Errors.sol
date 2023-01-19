// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

library Errors {
    string public constant AAVE_TOKEN_ADDRESS = "AaveTokenAddress";
    string public constant TICKS = "Ticks";
    string public constant DEPOSIT_RECEIVER = "DepositReceiver";
    string public constant DEPOSIT_CAP_OVER = "DepositCapOver";
    string public constant TOTAL_DEPOSIT_CAP_OVER = "TotalDepositCapOver";
    string public constant DEPOSIT_ZERO = "DepositZero";
    string public constant REDEEM_ZERO = "RedeemZero";
    string public constant ADD_LIQUIDITY_AMOUNTS = "AddLiquidityAmounts";
    string public constant PARAMS_CAP = "ParamsCap";
    string public constant PARAMS_BPS = "ParamsBps";
    string public constant PARAMS_INTERVAL = "ParamsInterval";
    string public constant PARAMS_LTV = "ParamsLtv";
    string public constant INCORRECT_LENGTH = "IncorrectLength";
    string public constant HIGH_SLIPPAGE = "HighSlippage";
    string public constant NEW_LIQUIDITY_ZERO = "NewLiquidityZero";
    string public constant CALLBACK_CALLER = "CallbackCaller";
    string public constant WHEN_CAN_STOPLOSS = "WhenCanStoploss";
    string public constant LESS_THAN_MIN_SHARES = "LessThanMinShares";
    string public constant LESS_THAN_MIN_ASSETS = "LessThanMinAssets";
    string public constant AAVE_MISMATCH = "AaveMismatch";
}
