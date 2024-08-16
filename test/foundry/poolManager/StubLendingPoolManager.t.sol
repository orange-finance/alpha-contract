// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {StubLendingPoolManager} from "../../../contracts/poolManager/StubLendingPoolManager.sol";
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
        poolManager.supply(100);
        assertEq(poolManager.balanceOfCollateral(), 0, "Supply does not effect collateral");
        assertEq(poolManager.balanceOfDebt(), 0, "Supply does not effect debt");
    }

    function test_withdraw() public {
        poolManager.withdraw(100);
        assertEq(poolManager.balanceOfCollateral(), 0, "Withdraw does not effect collateral");
        assertEq(poolManager.balanceOfDebt(), 0, "Withdraw does not effect debt");
    }

    function test_borrow() public {
        poolManager.borrow(100);
        assertEq(poolManager.balanceOfDebt(), 0, "Borrow does not effect debt");
        assertEq(poolManager.balanceOfCollateral(), 0, "Borrow does not effect collateral");
    }

    function test_repay() public {
        poolManager.repay(100);
        assertEq(poolManager.balanceOfDebt(), 0, "Repay does not effect debt");
        assertEq(poolManager.balanceOfCollateral(), 0, "Repay does not effect collateral");
    }
}
