// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@src/operation/factory/OrangeVaultFactoryV1_0.sol";
import {ILendingPoolManager} from "@src/interfaces/ILendingPoolManager.sol";
import {StubLendingPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/lendingPool/Stub.sol";

contract StubLendingPoolManagerDeployerTest is Test {
    StubLendingPoolManagerDeployer public deployer;

    function setUp() public {
        deployer = new StubLendingPoolManagerDeployer();
    }

    function test_deployPoolManager() public {
        address poolManager = address(deployer.deployPoolManager(address(0), address(0), address(0), bytes("")));
        IPoolManager(poolManager).setVault(address(0));
        assertTrue(address(poolManager) != address(0), "PoolManager should be deployed. setVault should not revert.");

        ILendingPoolManager lm = ILendingPoolManager(poolManager);

        (uint256 collateral, uint256 debt) = lm.balances();
        assertEq(collateral, 0, "Collateral should be 0.");
        assertEq(debt, 0, "Debt should be 0.");

        assertEq(lm.balanceOfCollateral(), 0, "Balance of collateral should be 0.");
        assertEq(lm.balanceOfDebt(), 0, "Balance of debt should be 0.");

        // should not revert
        lm.supply(100 ether);
        lm.withdraw(100 ether);
        lm.borrow(100 ether);
        lm.repay(100 ether);
    }
}
