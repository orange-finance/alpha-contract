// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import {ILendingPoolManager, IAaveV3Pool, AaveLendingPoolManager} from "../../../contracts/poolManager/AaveLendingPoolManager.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract AaveLendingPoolManagerTest is BaseTest {
    using SafeERC20 for IERC20;
    using Ints for int24;
    using Ints for int256;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.AaveAddr public aaveAddr;

    AaveLendingPoolManager public lendingPool;
    IAaveV3Pool public aave;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public aToken0;
    IERC20 public debtToken1;

    function setUp() public virtual {
        (tokenAddr, aaveAddr, ) = AddressHelper.addresses(block.chainid);

        aave = IAaveV3Pool(aaveAddr.poolAddr);
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);

        lendingPool = new AaveLendingPoolManager(address(this), address(token0), address(token1), address(aave));

        aToken0 = lendingPool.aToken0();
        debtToken1 = lendingPool.debtToken1();

        //deal
        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);

        //approve
        token0.approve(address(lendingPool), type(uint256).max);
        token1.approve(address(lendingPool), type(uint256).max);
    }

    function test_constructor() public {
        assertEq(address(lendingPool.aToken0()), aaveAddr.awethAddr);
        assertEq(address(lendingPool.debtToken1()), aaveAddr.vDebtUsdcAddr);
    }

    function test_onlyOperator_Revert() public {
        vm.expectRevert(bytes("ONLY_VAULT"));
        vm.prank(alice);
        lendingPool.supply(0);

        vm.expectRevert(bytes("ONLY_VAULT"));
        vm.prank(alice);
        lendingPool.withdraw(0);

        vm.expectRevert(bytes("ONLY_VAULT"));
        vm.prank(alice);
        lendingPool.borrow(0);

        vm.expectRevert(bytes("ONLY_VAULT"));
        vm.prank(alice);
        lendingPool.repay(0);
    }

    function test_all_Success() public {
        lendingPool.supply(10 ether);
        assertEq(token0.balanceOf(address(this)), 10_000 ether - 10 ether);
        assertEq(lendingPool.balanceOfCollateral(), 10 ether);
        skip(1);
        lendingPool.borrow(10_000 * 1e6);
        assertEq(token1.balanceOf(address(this)), (10_000 * 1e6) + (10_000_000 * 1e6));
        assertEq(lendingPool.balanceOfDebt(), 10_000 * 1e6);
        skip(1);
        uint debtBalance = debtToken1.balanceOf(address(lendingPool));
        lendingPool.repay(10_000 * 1e6);
        assertEq(token1.balanceOf(address(this)), 10_000_000 * 1e6);
        assertEq(lendingPool.balanceOfDebt(), debtBalance - (10_000 * 1e6));
        skip(1);
        uint aTokenBalance = aToken0.balanceOf(address(lendingPool));
        lendingPool.withdraw(10 ether);
        assertEq(token0.balanceOf(address(this)), 10_000 ether);
        assertEq(aToken0.balanceOf(address(lendingPool)), aTokenBalance - 10 ether);
    }
}
