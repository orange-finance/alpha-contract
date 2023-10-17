// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {OrangeStrategyHelperV1} from "../../coreV1/OrangeStrategyHelperV1.sol";
import {IResolver} from "../../interfaces/IResolver.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

/**
 * @title OrangeStoplossChecker
 * @author Orange Finance
 * @dev Checks if the stoploss condition is met for each vault. If yes, it will batch call the stoploss function of each vault.
 */
contract OrangeStoplossChecker is IResolver, AccessControlEnumerable {
    bytes32 public constant BATCH_CALLER = keccak256("BATCH_CALLER");

    address[] public vaults;
    mapping(address => OrangeStrategyHelperV1) public helpers;

    error RawCallFailed();

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Checks if the stoploss condition is met for at least one vault. If yes, it will batch call the stoploss function of each target vault.
     * @return _canExec Whether the stoploss condition is met for at least one vault.
     * @return _execPayload The payload to batch call the stoploss function of each target vault.
     */
    function checker() external view returns (bool _canExec, bytes memory _execPayload) {
        address[] memory _targets = new address[](vaults.length);
        bytes[] memory _payloads = new bytes[](vaults.length);

        uint256 j = 0;
        for (uint256 i = 0; i < vaults.length; i++) {
            address _vault = vaults[i];
            OrangeStrategyHelperV1 _helper = helpers[_vault];

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
     * @param _vaults The target vaults.
     * @param _payloads The payloads to call the stoploss function of each target vault.
     */
    function stoplossBatch(address[] calldata _vaults, bytes[] calldata _payloads) external onlyRole(BATCH_CALLER) {
        for (uint256 i = 0; i < _vaults.length; i++) {
            // * NOTES: if _vaults[i] is address(0), it means the all vaults are processed
            address _vault = _vaults[i];
            if (_vault == address(0)) return;

            address _helper = address(helpers[_vault]);
            (bool _ok, ) = _helper.call(_payloads[i]);
            if (!_ok) revert RawCallFailed();
        }
    }

    /**
     * @dev Adds a new vault to the list. only admin can call this function.
     * @param _vault The address of the new vault.
     * @param _helper The address of the new vault's helper.
     */
    function addVault(address _vault, address _helper) public onlyRole(DEFAULT_ADMIN_ROLE) {
        helpers[_vault] = OrangeStrategyHelperV1(_helper);
        vaults.push(_vault);
    }
}
