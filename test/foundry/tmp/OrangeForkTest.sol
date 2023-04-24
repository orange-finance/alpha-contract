// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import {OrangeAlphaVault, IERC20, IOrangeAlphaVault} from "../../../contracts/core/OrangeAlphaVault.sol";
import {OrangeAlphaParameters} from "../../../contracts/core/OrangeAlphaParameters.sol";

contract OrangeForkTest is BaseTest {
    OrangeAlphaVault public vault;
    OrangeAlphaParameters public params;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public debtToken0; //weth
    IERC20 public aToken1; //usdc

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.AaveAddr public aaveAddr;
    AddressHelper.UniswapAddr public uniswapAddr;

    function setUp() public {
        console2.log("setUp");
        console2.log("address(this)", address(this));
        (tokenAddr, aaveAddr, uniswapAddr) = AddressHelper.addresses(block.chainid);
        vault = OrangeAlphaVault(address(0));
        params = OrangeAlphaParameters(address(vault.params()));

        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);
        debtToken0 = IERC20(aaveAddr.vDebtWethAddr);
        aToken1 = IERC20(aaveAddr.ausdcAddr);

        deal(tokenAddr.wethAddr, address(this), 10_000 ether);

        vm.prank(address(0));
        params.setStrategist(address(this), true);
    }

    function test_rebalance() public {
        int24 lower_range_tick = -200820;
        int24 upper_range_tick = -199770;
        int24 stoploss_lower_tick = -201120;
        int24 stoploss_upper_tick = -199470;
        uint hedge = 209054433;

        // int24 lower_range_tick = -200520;
        // int24 upper_range_tick = -199520;
        // int24 stoploss_lower_tick = -200820;
        // int24 stoploss_upper_tick = -199230;
        // uint hedge = 205982304;
        vault.rebalance(lower_range_tick, upper_range_tick, stoploss_lower_tick, stoploss_upper_tick, hedge, 0);
    }

    function consoleCurrentPosition() internal view {
        console2.log("++++++++++++++++consoleCurrentPosition++++++++++++++++");
        console2.log(debtToken0.balanceOf(address(vault)), "debtAmount0");
        console2.log(aToken1.balanceOf(address(vault)), "supplyAmount1");
        console2.log("++++++++++++++++consoleCurrentPosition++++++++++++++++");
    }
}
