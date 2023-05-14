// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangePoolManagerProxy} from "../interfaces/IOrangePoolManagerProxy.sol";
import {Ownable} from "../libs/Ownable.sol";
import {Clone} from "../libs/Clone.sol";

contract PoolManagerFactory is Ownable {
    /* ========== EVENTS ========== */
    event TemplateApproved(address _manager, bool _approval);
    event PoolManagerCreated(
        address indexed _template,
        address indexed _manager,
        address _operator,
        address _token0,
        address _token1,
        uint256[] _params,
        address[] _references
    );

    /* ========== STORAGES ========== */
    mapping(address => bool) public templates;

    /* ========== FUNCTIONS ========== */
    function approveTemplate(IOrangePoolManagerProxy _template, bool _approval) external onlyOwner {
        if (address(_template) == address(0)) revert("PoolManagerFactory: Zero address");
        templates[address(_template)] = _approval;

        emit TemplateApproved(address(_template), _approval);
    }

    function create(
        address _implementation,
        address _operator,
        address _token0,
        address _token1,
        uint256[] calldata _params,
        address[] calldata _references
    ) external returns (address) {
        if (!templates[_implementation]) revert("PoolManagerFactory: Unauthorized template");

        address _manager = Clone.clone(_implementation);
        IOrangePoolManagerProxy(_manager).initialize(_operator, _token0, _token1, _params, _references);

        emit PoolManagerCreated(_implementation, _manager, _operator, _token0, _token1, _params, _references);
        return _manager;
    }
}
