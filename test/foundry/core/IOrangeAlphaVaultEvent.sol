// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";

interface IOrangeAlphaVaultEvent {
    /* ========== EVENTS ========== */
    event BurnAndCollectFees(
        uint256 burn0,
        uint256 burn1,
        uint256 fee0,
        uint256 fee1
    );

    /**
     * @notice actionTypes
     * 0. executed manually
     * 1. deposit
     * 2. redeem
     * 3. rebalance
     * 4. stoploss
     */
    event Action(
        uint8 indexed actionType,
        address indexed caller,
        uint256 totalAssets,
        uint256 totalSupply
    );
}
