// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BaseTest} from "@test/foundry/utils/BaseTest.sol";
import {OrangeVaultFactoryV1_0} from "@src/operation/factory/OrangeVaultFactoryV1_0.sol";
import {OrangeStrategyImplV1} from "@src/coreV1/OrangeStrategyImplV1.sol";
import {OrangeVaultRegistry} from "@src/operation/registry/OrangeVaultRegistry.sol";
import {OrangeVaultV1Initializable} from "@src/coreV1/proxy/OrangeVaultV1Initializable.sol";

contract Fixture is BaseTest {
    OrangeVaultFactoryV1_0 public factory;
    OrangeVaultRegistry public registry;
    OrangeVaultV1Initializable public vaultImpl;
    OrangeStrategyImplV1 public strategyImpl;

    function _deployFactory(address _admin) internal {
        vm.startPrank(_admin);
        strategyImpl = new OrangeStrategyImplV1();
        vaultImpl = new OrangeVaultV1Initializable();
        factory = new OrangeVaultFactoryV1_0({
            _registry: address(registry),
            _strategyImpl: address(strategyImpl),
            _vaultImpl: address(vaultImpl)
        });
        vm.stopPrank();
    }
}
