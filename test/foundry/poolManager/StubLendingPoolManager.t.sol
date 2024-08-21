// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {StubLendingPoolManager, StubLendingPoolManager__NotImplemented} from "../../../contracts/poolManager/StubLendingPoolManager.sol";
import {Test} from "forge-std/Test.sol";

contract StubLendingPoolManagerTest is Test {
    StubLendingPoolManager public poolManager;

    function setUp() public {
        poolManager = new StubLendingPoolManager();
    }

    function test_balances() public {
        (uint256 collateral, uint256 debt) = poolManager.balances();
        assertEq(collateral, 0, "Collateral should be 0");
        assertEq(debt, 0, "Debt should be 0");
    }

    function test_balanceOfCollateral() public {
        assertEq(poolManager.balanceOfCollateral(), 0, "Collateral should be 0");
    }

    function test_balanceOfDebt() public {
        assertEq(poolManager.balanceOfDebt(), 0, "Debt should be 0");
    }

    function test_supply() public {
        vm.expectRevert(StubLendingPoolManager__NotImplemented.selector);
        poolManager.supply(100);
    }

    function test_withdraw() public {
        vm.expectRevert(StubLendingPoolManager__NotImplemented.selector);
        poolManager.withdraw(100);
    }

    function test_borrow() public {
        vm.expectRevert(StubLendingPoolManager__NotImplemented.selector);
        poolManager.borrow(100);
    }

    function test_repay() public {
        vm.expectRevert(StubLendingPoolManager__NotImplemented.selector);
        poolManager.repay(100);
    }

    function test_setVault() public view {
        poolManager.setVault(address(0));
    }
}
