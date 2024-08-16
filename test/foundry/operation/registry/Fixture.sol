// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {BaseTest} from "@test/foundry/utils/BaseTest.sol";
import {OrangeVaultRegistry} from "@src/operation/registry/OrangeVaultRegistry.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract Fixture is BaseTest {
    OrangeVaultRegistry public orangeVaultRegistry;

    event VaultAdded(address indexed vault, string indexed version, address indexed parameters);
    event VaultRemoved(address indexed vault);

    function _deployRegistry(address _admin, address _vaultDeployer) internal {
        vm.startPrank(_admin);
        orangeVaultRegistry = new OrangeVaultRegistry();
        orangeVaultRegistry.grantRole(orangeVaultRegistry.VAULT_DEPLOYER_ROLE(), _vaultDeployer);
        vm.stopPrank();
    }

    function _expectEmits() internal {
        vm.expectEmit(true, true, true, true);
    }
}
