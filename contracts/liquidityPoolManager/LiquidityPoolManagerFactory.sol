// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IProxy} from "../interfaces/IProxy.sol";

contract LiquidityPoolManagerFactory {
    /**
     * EVENTS
     */
    event ManagerApproved(address _manager, bool _approval);
    event ManagerCreated(address indexed _template, address indexed _manager, uint256[] _params, address[] _references);
    /**
     * ERRORS
     */
    error ZeroAddress();
    error UnauthorizedManager();

    mapping(address => bool) public templates;

    /// @notice inherit IPolicyFactory
    function approveTemplate(IProxy _template, bool _approval) external {
        if (address(_template) == address(0)) revert ZeroAddress();
        templates[address(_template)] = _approval;

        emit ManagerApproved(address(_template), _approval);
    }

    /// @notice inherit IPolicyFactory
    function create(
        IProxy _template,
        uint256[] calldata _params,
        address[] calldata _references
    ) external returns (address) {
        if (!templates[address(_template)]) revert UnauthorizedManager();

        IProxy _manager = IProxy(_createClone(address(_template)));

        _manager.initialize(_params, _references);
        emit ManagerCreated(address(_template), address(_manager), _params, _references);
        return address(_manager);
    }

    /**
     * @notice manager Code for the create clone method:
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1167.md
     */
    function _createClone(address target) internal returns (address result) {
        // convert address to bytes20 for assembly use
        bytes20 targetBytes = bytes20(target);
        assembly {
            // allocate clone memory
            let clone := mload(0x40)
            // store initial portion of the delegation contract code in bytes form
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            // store the provided address
            mstore(add(clone, 0x14), targetBytes)
            // store the remaining delegation contract code
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            // create the actual delegate contract reference and return its address
            result := create(0, clone, 0x37)
        }

        if (result == address(0)) revert ZeroAddress();
    }
}
