// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IBalancerVault, IBalancerFlashLoanRecipient, IERC20} from "../interfaces/IBalancerFlashloan.sol";

library BalancerFlashloan {
    ///@notice make parameters and execute Flashloan
    function makeFlashLoan(
        IBalancerVault _vault,
        IBalancerFlashLoanRecipient _receiver,
        IERC20 _token,
        uint256 _amount,
        bytes memory _userData
    ) internal {
        IERC20[] memory _tokensFlashloan = new IERC20[](1);
        _tokensFlashloan[0] = _token;
        uint256[] memory _amountsFlashloan = new uint256[](1);
        _amountsFlashloan[0] = _amount;
        _vault.flashLoan(_receiver, _tokensFlashloan, _amountsFlashloan, _userData);
    }
}
