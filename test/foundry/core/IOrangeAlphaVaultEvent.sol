// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";

interface IOrangeAlphaVaultEvent {
    event Action(
        IOrangeAlphaVault.ActionType indexed actionType,
        address indexed caller,
        uint256 totalAssets,
        uint256 totalSupply
    );
}
