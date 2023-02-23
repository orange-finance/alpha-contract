// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IResolver} from "../vendor/gelato/IResolver.sol";
import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaResolver is IResolver {
    /* ========== STORAGES ========== */
    IOrangeAlphaVault vault;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault) {
        vault = IOrangeAlphaVault(_vault);
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
            !vault.canStoploss(
                _currentTick,
                _getTwap(),
                vault.stoplossLowerTick(),
                vault.stoplossUpperTick()
            )
        ) {
            return (false, bytes("can not stoploss"));
        } else {
            execPayload = abi.encodeWithSelector(
                IOrangeAlphaVault.stoploss.selector,
                _currentTick
            );
            return (true, execPayload);
        }
    }

    function _getTwap() internal view virtual returns (int24 avgTick) {
        IUniswapV3Pool _pool = vault.pool();

        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = 5 minutes;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = _pool.observe(secondsAgo);

        require(tickCumulatives.length == 2, "array len");
        unchecked {
            avgTick = int24(
                (tickCumulatives[1] - tickCumulatives[0]) /
                    int56(uint56(5 minutes))
            );
        }
    }
}
