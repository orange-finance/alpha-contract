// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";
import {IResolver} from "../vendor/gelato/IResolver.sol";
import {UniswapV3Twap, IUniswapV3Pool} from "../libs/UniswapV3Twap.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaResolver is IResolver {
    using UniswapV3Twap for IUniswapV3Pool;

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
    function checker()
        external
        view
        override
        returns (bool canExec, bytes memory execPayload)
    {
        IUniswapV3Pool _pool = vault.pool();
        (, int24 _currentTick, , , , , ) = _pool.slot0();
        if (
            vault.canStoploss(
                _currentTick,
                vault.stoplossLowerTick(),
                vault.stoplossUpperTick()
            )
        ) {
            int24 _twap = _pool.getTwap();
            if (
                vault.canStoploss(
                    _twap,
                    vault.stoplossLowerTick(),
                    vault.stoplossUpperTick()
                )
            ) {
                execPayload = abi.encodeWithSelector(
                    IOrangeAlphaVault.stoploss.selector,
                    _twap
                );
                return (true, execPayload);
            }
        }
        return (false, bytes(ERROR_CANNOT_STOPLOSS));
    }
}
