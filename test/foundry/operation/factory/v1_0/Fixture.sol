// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "@test/foundry/utils/BaseTest.sol";
import {MockPoolManagerDeployer} from "@test/foundry/operation/mocks/MockPoolManagerDeployer.sol";
import {MockPoolManager} from "@test/foundry/operation/mocks/MockPoolManager.sol";
import {MockERC20} from "@test/foundry/mocks/MockERC20.sol";
import {OrangeVaultFactoryV1_0} from "@src/operation/factory/OrangeVaultFactoryV1_0.sol";
import {OrangeStrategyImplV1Initializable} from "@src/coreV1/proxy/OrangeStrategyImplV1Initializable.sol";
import {OrangeVaultRegistry} from "@src/operation/registry/OrangeVaultRegistry.sol";
import {OrangeVaultV1Initializable} from "@src/coreV1/proxy/OrangeVaultV1Initializable.sol";

contract Fixture is BaseTest {
    OrangeVaultFactoryV1_0 public factory;
    OrangeVaultRegistry public registry;
    OrangeVaultV1Initializable public vaultImpl;
    OrangeStrategyImplV1Initializable public strategyImpl;
    MockPoolManagerDeployer public mockLiquidityPoolManagerDeployer;
    MockPoolManagerDeployer public mockLendingPoolManagerDeployer;
    MockPoolManager public mockLiquidityPoolManager;
    MockPoolManager public mockLendingPoolManager;
    MockERC20 public mockToken0;
    MockERC20 public mockToken1;

    function _deployFactory(address _admin) internal {
        vm.startPrank(_admin);
        mockLiquidityPoolManagerDeployer = new MockPoolManagerDeployer();
        mockLendingPoolManagerDeployer = new MockPoolManagerDeployer();
        mockLiquidityPoolManager = new MockPoolManager();
        mockLendingPoolManager = new MockPoolManager();
        mockToken0 = new MockERC20("MockToken0", "MT0");
        mockToken1 = new MockERC20("MockToken1", "MT1");
        registry = new OrangeVaultRegistry();
        strategyImpl = new OrangeStrategyImplV1Initializable();
        vaultImpl = new OrangeVaultV1Initializable();
        factory = new OrangeVaultFactoryV1_0({
            _registry: address(registry),
            _strategyImpl: address(strategyImpl),
            _vaultImpl: address(vaultImpl)
        });
        registry.grantRole(registry.VAULT_DEPLOYER_ROLE(), address(factory));
        vm.stopPrank();

        mockLiquidityPoolManagerDeployer.setPoolManagerReturnValue(address(mockLiquidityPoolManager));
        mockLendingPoolManagerDeployer.setPoolManagerReturnValue(address(mockLendingPoolManager));
    }
}
