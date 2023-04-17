// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "./IWETH.sol";

import {BalancerFlashloan, IERC20} from "../../../contracts/mocks/BalancerFlashloan.sol";

contract BalancerFlashloanTest is BaseTest {
    AddressHelper.TokenAddr public tokenAddr;

    BalancerFlashloan balancer;
    IERC20 usdc;
    IERC20 weth;

    function setUp() public {
        (tokenAddr, , ) = AddressHelper.addresses(block.chainid);

        usdc = IERC20(tokenAddr.usdcAddr);
        weth = IERC20(tokenAddr.wethAddr);

        balancer = new BalancerFlashloan();

        deal(tokenAddr.usdcAddr, address(this), 10_000 * 1e6);
    }

    function test_makeFlashLoanUsdc() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = usdc;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123;

        balancer.makeFlashLoan(tokens, amounts, "");
    }

    function test_makeFlashLoanWeth() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = weth;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123 * 1e18;

        balancer.makeFlashLoan(tokens, amounts, "");
    }

    function test_makeFlashLoanUsdcZero() public {
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = usdc;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;

        balancer.makeFlashLoan(tokens, amounts, "");
    }
}
