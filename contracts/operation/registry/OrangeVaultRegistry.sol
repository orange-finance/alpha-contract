// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeVaultRegistry} from "@src/operation/registry/IOrangeVaultRegistry.sol";
import {Strings} from "@src/libs/Strings.sol";
import {AddressZero, EmptyString} from "@src/operation/Errors.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title OrangeVaultRegistry contract
 * @author Orange Finance
 * @notice Registry for vaults.
 * @dev This contract is used to keep track of all vaults.
 */
contract OrangeVaultRegistry is IOrangeVaultRegistry, AccessControlEnumerable {
    using Strings for string;

    bytes32 public constant VAULT_DEPLOYER_ROLE = keccak256("VAULT_DEPLOYER_ROLE");

    uint256 public numVaults;
    mapping(address => VaultDetail) public vaultDetails;

    error VaultAlreadyAdded(address vault);
    error VaultNotFound(address vault);

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @inheritdoc IOrangeVaultRegistry
    function getDetailOf(address _vault) external view override returns (VaultDetail memory) {
        return vaultDetails[_vault];
    }

    /**
     * @inheritdoc IOrangeVaultRegistry
     * @dev Only callable by the vault deployer assumed to be the OrangeVaultFactory contract.
     */
    function add(
        address _vault,
        string calldata _version,
        address _parameters
    ) external override onlyRole(VAULT_DEPLOYER_ROLE) {
        if (_vault == address(0) || _parameters == address(0)) revert AddressZero();
        if (_version.equal("")) revert EmptyString();
        if (!vaultDetails[_vault].version.equal("")) revert VaultAlreadyAdded(_vault);

        vaultDetails[_vault] = VaultDetail({version: _version, parameters: _parameters});
        unchecked {
            numVaults++;
        }

        emit VaultAdded(_vault, _version, _parameters);
    }

    /// @inheritdoc IOrangeVaultRegistry
    /// @dev Only callable by the admin  account.
    function remove(address _vault) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (vaultDetails[_vault].version.equal("")) revert VaultNotFound(_vault);
        delete vaultDetails[_vault];
        unchecked {
            numVaults--;
        }
        emit VaultRemoved(_vault);
    }
}
