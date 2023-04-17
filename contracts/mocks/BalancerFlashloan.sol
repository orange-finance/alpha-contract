// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IVault} from "../interfaces/IVault.sol";
import {IFlashLoanRecipient, IERC20} from "../interfaces/IFlashLoanRecipient.sol";

import "forge-std/console2.sol";

contract BalancerFlashloan is IFlashLoanRecipient {
    address private constant vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    function makeFlashLoan(IERC20[] memory tokens, uint256[] memory amounts, bytes memory userData) external {
        IVault(vault).flashLoan(this, tokens, amounts, userData);
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override {
        require(msg.sender == vault);
        console2.log("amounts:", amounts[0]);
        IERC20(tokens[0]).approve(vault, type(uint256).max);
        IERC20(tokens[0]).transfer(vault, amounts[0]);
    }
}
