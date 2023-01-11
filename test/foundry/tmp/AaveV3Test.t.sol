// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IWETH.sol";

import {IAaveV3Pool} from "../../../contracts/interfaces/IAaveV3Pool.sol";
import {IPriceOracleGetter} from "../../../contracts/interfaces/IPriceOracleGetter.sol";
import {DataTypes} from "../../../contracts/vendor/aave/DataTypes.sol";

contract AaveV3Test is BaseTest {
    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.AaveAddr public aaveAddr;

    IERC20 usdc;
    IERC20 ausdc;
    IWETH weth;
    IERC20 vDebtWeth;
    IAaveV3Pool aave;
    IPriceOracleGetter aaveOracle;

    function setUp() public {
        (tokenAddr, aaveAddr, ) = AddressHelper.addresses(block.chainid);

        usdc = IERC20(tokenAddr.usdcAddr);
        ausdc = IERC20(aaveAddr.ausdcAddr);
        weth = IWETH(tokenAddr.wethAddr);
        vDebtWeth = IERC20(aaveAddr.vDebtWethAddr);
        aave = IAaveV3Pool(aaveAddr.poolAddr);
        aaveOracle = IPriceOracleGetter(aaveAddr.aaveOracleAddr);

        deal(tokenAddr.usdcAddr, address(this), 10_000 * 1e6);
        usdc.approve(aaveAddr.poolAddr, type(uint256).max);
        weth.approve(aaveAddr.poolAddr, type(uint256).max);
    }

    function testSupplyUsdcBorrowWeth() public {
        aave.supply(tokenAddr.usdcAddr, 10_000 * 1e6, address(this), 0);
        assertEq(usdc.balanceOf(address(this)), 0);
        assertApproxEqRel(ausdc.balanceOf(address(this)), 10_000 * 1e6, 1e15); //0.1%
        skip(1);
        aave.borrow(tokenAddr.wethAddr, 2 ether, 2, 0, address(this));
        assertEq(weth.balanceOf(address(this)), 2 ether);
        assertApproxEqRel(vDebtWeth.balanceOf(address(this)), 2 ether, 1e15); //0.1%
        skip(1);
        aave.repay(tokenAddr.wethAddr, 1 ether, 2, address(this));
        assertEq(weth.balanceOf(address(this)), 1 ether);
        assertApproxEqRel(vDebtWeth.balanceOf(address(this)), 1 ether, 1e15); //0.1%
        skip(1);
        aave.withdraw(tokenAddr.usdcAddr, 2_000 * 1e6, address(this));
        assertEq(usdc.balanceOf(address(this)), 2_000 * 1e6);
    }

    function testOracle() public {
        uint256 priceUsdc = aaveOracle.getAssetPrice(address(usdc));
        uint256 priceWeth = aaveOracle.getAssetPrice(address(weth));
        console2.log(priceUsdc, "priceUsdc");
        console2.log(priceWeth, "priceWeth");
    }

    function testGetLtv() public {
        aave.supply(tokenAddr.usdcAddr, 10_000 * 1e6, address(this), 0);
        aave.borrow(tokenAddr.wethAddr, 2 ether, 2, 0, address(this));

        uint256 token0Price = aaveOracle.getAssetPrice(address(weth));
        uint256 token1Price = aaveOracle.getAssetPrice(address(usdc));
        uint256 _debtBalance = vDebtWeth.balanceOf(address(this));
        uint256 _collateralBalance = ausdc.balanceOf(address(this));
        //align decimals weth to usdc
        uint256 _ltv = (((token0Price * _debtBalance) / 1e12) * 1e8) /
            (token1Price * _collateralBalance);
        console2.log(_ltv, "_ltv");
    }

    function testGetLtvAave() public {
        aave.supply(tokenAddr.usdcAddr, 10_000 * 1e6, address(this), 0);
        skip(1);
        aave.borrow(tokenAddr.wethAddr, 2 ether, 2, 0, address(this));

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            ,
            uint256 ltv,

        ) = aave.getUserAccountData(address(this));
        console2.log(ltv, "ltv");
        // this ltv gets only 8000. does it get max ltv?

        ltv = (totalDebtBase * 1e8) / totalCollateralBase;
        console2.log(ltv, "ltv");
    }

    function testAtokenAddress() public {
        DataTypes.ReserveData memory reserveDataUsdc = aave.getReserveData(
            address(usdc)
        );
        DataTypes.ReserveData memory reserveDataWeth = aave.getReserveData(
            address(weth)
        );
        assertEq(reserveDataUsdc.aTokenAddress, aaveAddr.ausdcAddr);
        assertEq(
            reserveDataUsdc.variableDebtTokenAddress,
            aaveAddr.vDebtUsdcAddr
        );
        assertEq(
            reserveDataUsdc.stableDebtTokenAddress,
            aaveAddr.sDebtUsdcAddr
        );
        assertEq(reserveDataWeth.aTokenAddress, aaveAddr.awethAddr);
        assertEq(
            reserveDataWeth.variableDebtTokenAddress,
            aaveAddr.vDebtWethAddr
        );
        assertEq(
            reserveDataWeth.stableDebtTokenAddress,
            aaveAddr.sDebtWethAddr
        );
    }
}
