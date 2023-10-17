// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {IResolver} from "../../interfaces/IResolver.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title OrangeStoplossChecker
 * @author Orange Finance
 * @dev Checks if the stoploss condition is met for each vault. If yes, it will batch call the stoploss function of each vault.
 */
contract OrangeStoplossChecker is IResolver, AccessControlEnumerable {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant BATCH_CALLER = keccak256("BATCH_CALLER");

    mapping(address => IResolver) public helpers;

    EnumerableSet.AddressSet _vaults;

    error RawCallFailed();

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Returns the address of the vault at the given index.
     */
    function getVaultAt(uint256 index) external view returns (address) {
        return _vaults.at(index);
    }

    /**
     * @dev Returns the number of vaults.
     */
    function getVaultCount() external view returns (uint256) {
        return _vaults.length();
    }

    /**
     * @dev Checks if the stoploss condition is met for at least one vault. If yes, it will batch call the stoploss function of each target vault.
     * @return canExec Whether the stoploss condition is met for at least one vault.
     * @return execPayload The payload to batch call the stoploss function of each target vault.
     */
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        uint256 _len = _vaults.length();
        address[] memory _targets = new address[](_len);
        bytes[] memory _payloads = new bytes[](_len);

        uint256 j = 0;
        for (uint256 i = 0; i < _len; i++) {
            address _vault = _vaults.at(i);
            IResolver _helper = helpers[_vault];

            (bool _can, bytes memory _payload) = _helper.checker();
            if (_can) {
                _targets[j] = _vault;
                _payloads[j] = _payload;
                j++;
            }
        }

        if (j > 0) return (true, abi.encodeWithSelector(this.stoplossBatch.selector, _targets, _payloads));

        return (false, bytes("OrangeStopLossChecker: No vaults to stoploss"));
    }

    /**
     * @dev Batch calls the stoploss function of each target vault. only batch caller can call this function.
     * batch caller is assumed to be a Gelato dedicated message sender
     * @param vaults_ The target vaults.
     * @param payloads The payloads to call the stoploss function of each target vault.
     */
    function stoplossBatch(address[] calldata vaults_, bytes[] calldata payloads) external onlyRole(BATCH_CALLER) {
        for (uint256 i = 0; i < vaults_.length; i++) {
            // * NOTES: if _vaults[i] is address(0), it means the all vaults are processed
            address _vault = vaults_[i];
            if (_vault == address(0)) return;

            address _helper = address(helpers[_vault]);
            (bool _ok, ) = _helper.call(payloads[i]);
            if (!_ok) revert RawCallFailed();
        }
    }

    /**
     * @dev Adds a new vault to the list. only admin can call this function.
     * @param vault The address of the new vault.
     * @param helper The address of the new vault's helper.
     */
    function addVault(address vault, address helper) public onlyRole(DEFAULT_ADMIN_ROLE) {
        helpers[vault] = IResolver(helper);
        _vaults.add(vault);
    }

    /**
     * @dev Removes a vault from the list. only admin can call this function.
     * @param vault The address of the vault to be removed.
     */
    function removeVault(address vault) public onlyRole(DEFAULT_ADMIN_ROLE) {
        delete helpers[vault];
        _vaults.remove(vault);
    }
}
