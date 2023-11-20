// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {Mock} from "@test/foundry/mocks/Mock.sol";
import {IOrangeVaultRegistry} from "@src/interfaces/IOrangeVaultRegistry.sol";

contract MockOrangeVaultRegistry is Mock, IOrangeVaultRegistry {
    mapping(address => VaultDetail) public vaultDetailReturns;

    function numVaults() external view returns (uint256) {
        bytes4 _sig = bytes4(keccak256("numVaults()"));
        return uint256Returns[_sig];
    }

    function getDetailOf(address _vault) external view returns (VaultDetail memory) {
        return vaultDetailReturns[_vault];
    }

    function add(
        address _vault,
        string calldata _version,
        address _parameters
    ) external mayRevert(IOrangeVaultRegistry.add.selector) {}

    function remove(address _vault) external mayRevert(IOrangeVaultRegistry.remove.selector) {}

    function setVaultDetailReturn(address _vault) public {
        bytes4 _sig = bytes4(keccak256("getDetailOf(address)"));
        stringReturns[_sig] = "v1";
        addressReturns[_sig] = _vault;
    }
}
