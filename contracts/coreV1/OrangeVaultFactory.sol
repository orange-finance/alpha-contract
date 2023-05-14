// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeVaultV1Proxy} from "../interfaces/IOrangeVaultV1.sol";
import {Ownable} from "../libs/Ownable.sol";
import {Clone} from "../libs/Clone.sol";

contract OrangeVaultFactory is Ownable {
    /* ========== EVENTS ========== */
    event TemplateApproved(address _manager, bool _approval);
    event VaultCreated(
        address indexed _implementation,
        address indexed _vault,
        address _token0,
        address _token1,
        address _poolFactory,
        address _liquidityTemplate,
        address[] _liquidityReferences,
        address _lendingTemplate,
        address[] _lendingReferences,
        address _params
    );

    /* ========== STORAGES ========== */
    mapping(address => bool) public templates;

    /* ========== FUNCTIONS ========== */
    function approveTemplate(IOrangeVaultV1Proxy _template, bool _approval) external onlyOwner {
        if (address(_template) == address(0)) revert("OrangeVaultFactory: Zero address");
        templates[address(_template)] = _approval;
        emit TemplateApproved(address(_template), _approval);
    }

    function create(
        address _implementation,
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        address _poolFactory,
        address _liquidityTemplate,
        address[] memory _liquidityReferences,
        address _lendingTemplate,
        address[] memory _lendingReferences,
        address _params
    ) external returns (address) {
        if (!templates[_implementation]) revert("OrangeVaultFactory: Unauthorized template");

        address _vault = Clone.clone(_implementation);
        IOrangeVaultV1Proxy(_vault).initialize(
            _name,
            _symbol,
            _token0,
            _token1,
            _poolFactory,
            _liquidityTemplate,
            _liquidityReferences,
            _lendingTemplate,
            _lendingReferences,
            _params
        );

        emit VaultCreated(
            _implementation,
            _vault,
            _token0,
            _token1,
            _poolFactory,
            _liquidityTemplate,
            _liquidityReferences,
            _lendingTemplate,
            _lendingReferences,
            _params
        );
        return _vault;
    }
}
