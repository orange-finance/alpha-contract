// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangePoolManagerProxy} from "../interfaces/IOrangePoolManagerProxy.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract PoolManagerFactory {
    /**
     * EVENTS
     */
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
    /**
     * ERRORS
     */
    error ZeroAddress();
    error UnauthorizedTemplate();

    mapping(address => bool) public templates;

    function approveTemplate(IOrangePoolManagerProxy _template, bool _approval) external {
        if (address(_template) == address(0)) revert ZeroAddress();
        templates[address(_template)] = _approval;

        emit TemplateApproved(address(_template), _approval);
    }

    function create(
        IOrangePoolManagerProxy _template,
        address _operator,
        address _token0,
        address _token1,
        uint256[] calldata _params,
        address[] calldata _references
    ) external returns (address) {
        if (!templates[address(_template)]) revert UnauthorizedTemplate();

        address _manager = Clones.clone(address(_template));
        IOrangePoolManagerProxy(_manager).initialize(_operator, _token0, _token1, _params, _references);

        emit PoolManagerCreated(address(_template), _manager, _operator, _token0, _token1, _params, _references);
        return _manager;
    }
}
