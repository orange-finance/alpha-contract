// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {BaseTest} from "@test/foundry/utils/BaseTest.sol";
import {Fixture} from "@test/foundry/operation/registry/Fixture.sol";
import {IOrangeVaultRegistry} from "@src/operation/registry/IOrangeVaultRegistry.sol";
import {OrangeVaultRegistry} from "@src/operation/registry/OrangeVaultRegistry.sol";
import {AddressZero, EmptyString} from "@src/operation/Errors.sol";
import {ErrorUtil} from "@test/foundry/utils/ErrorUtil.sol";

contract OrangeVaultRegistryTest is Fixture {
    function setup() public {
        _setUp();
    }

    function test_add__Success() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x1);
        address _parameters = address(0x2);

        IOrangeVaultRegistry.VaultDetail memory _detail = orangeVaultRegistry.getDetailOf(_vault);
        assertEq(_detail.version, "", "version should be 0 before add");
        assertEq(_detail.parameters, address(0), "parameters should be 0 before add");

        string memory _version = "v1 extended";

        _expectEmits();
        emit VaultAdded(_vault, "v1 extended", _parameters);
        vm.prank(bob);
        orangeVaultRegistry.add(_vault, _version, _parameters);

        _detail = orangeVaultRegistry.getDetailOf(_vault);

        assertEq(_detail.version, _version, "version should be set after add");
        assertEq(_detail.parameters, _parameters, "parameters should be set after add");
    }

    function test_add__Fail_AddressZero() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x0);
        address _parameters = address(0x2);

        vm.expectRevert(AddressZero.selector);
        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "1", _parameters);

        _vault = address(0x1);
        _parameters = address(0x0);

        vm.expectRevert(AddressZero.selector);
        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "1", _parameters);
    }

    function test_add__Fail_EmptyString() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x1);
        address _parameters = address(0x2);

        vm.expectRevert(EmptyString.selector);
        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "", _parameters);
    }

    function test_add__Fail_AlreadyAdded() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x1);
        address _parameters = address(0x2);

        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "1", _parameters);

        vm.expectRevert(abi.encodeWithSelector(OrangeVaultRegistry.VaultAlreadyAdded.selector, _vault));
        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "1", _parameters);

        vm.expectRevert(abi.encodeWithSelector(OrangeVaultRegistry.VaultAlreadyAdded.selector, _vault));
        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "2", _parameters);
    }

    function test_add__Fail_NotDeployer() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x1);
        address _parameters = address(0x2);

        bytes memory _aliceIsNotDeployer = ErrorUtil.roleError(alice, orangeVaultRegistry.VAULT_DEPLOYER_ROLE());
        vm.expectRevert(_aliceIsNotDeployer);
        vm.prank(alice);
        orangeVaultRegistry.add(_vault, "1", _parameters);
    }

    function test_remove__Success() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x1);
        address _parameters = address(0x2);

        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "1", _parameters);

        _expectEmits();
        emit VaultRemoved(_vault);
        vm.prank(alice);
        orangeVaultRegistry.remove(_vault);

        IOrangeVaultRegistry.VaultDetail memory _detail = orangeVaultRegistry.getDetailOf(_vault);
        assertEq(_detail.version, "");
        assertEq(_detail.parameters, address(0));
    }

    function test_remove__Fail_NotFound() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x1);

        vm.expectRevert(abi.encodeWithSelector(OrangeVaultRegistry.VaultNotFound.selector, _vault));
        vm.prank(alice);
        orangeVaultRegistry.remove(_vault);
    }

    function test_remove__Fail_RemoveAddressZero() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x0);

        vm.expectRevert(abi.encodeWithSelector(OrangeVaultRegistry.VaultNotFound.selector, _vault));
        vm.prank(alice);
        orangeVaultRegistry.remove(_vault);
    }

    function test_remove__Fail_NotAdmin() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        address _vault = address(0x1);
        address _parameters = address(0x2);

        vm.prank(bob);
        orangeVaultRegistry.add(_vault, "1", _parameters);

        bytes memory _bobIsNotAdmin = ErrorUtil.roleError(bob, orangeVaultRegistry.DEFAULT_ADMIN_ROLE());
        vm.expectRevert(_bobIsNotAdmin);
        vm.prank(bob);
        orangeVaultRegistry.remove(_vault);
    }

    function test_numVaults() public {
        _deployRegistry({_admin: alice, _vaultDeployer: bob});
        assertEq(orangeVaultRegistry.numVaults(), 0);

        address _vault1 = address(0x1);
        address _parameters1 = address(0x2);
        address _vault2 = address(0x3);
        address _parameters2 = address(0x4);

        vm.prank(bob);
        orangeVaultRegistry.add(_vault1, "1", _parameters1);
        assertEq(orangeVaultRegistry.numVaults(), 1);

        vm.prank(alice);
        orangeVaultRegistry.remove(_vault1);
        assertEq(orangeVaultRegistry.numVaults(), 0);

        vm.prank(bob);
        orangeVaultRegistry.add(_vault1, "1", _parameters1);
        assertEq(orangeVaultRegistry.numVaults(), 1);

        vm.prank(bob);
        orangeVaultRegistry.add(_vault2, "2", _parameters2);
        assertEq(orangeVaultRegistry.numVaults(), 2);

        vm.prank(alice);
        orangeVaultRegistry.remove(_vault1);
        assertEq(orangeVaultRegistry.numVaults(), 1);

        vm.prank(alice);
        orangeVaultRegistry.remove(_vault2);
        assertEq(orangeVaultRegistry.numVaults(), 0);
    }
}
