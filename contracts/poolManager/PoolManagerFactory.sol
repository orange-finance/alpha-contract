// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangePoolManagerProxy} from "../interfaces/IOrangePoolManagerProxy.sol";

contract PoolManagerFactory {
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
    function approveTemplate(IOrangePoolManagerProxy _template, bool _approval) external {
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

        address _manager = _clone(_implementation);
        IOrangePoolManagerProxy(_manager).initialize(_operator, _token0, _token1, _params, _references);

        emit PoolManagerCreated(_implementation, _manager, _operator, _token0, _token1, _params, _references);
        return _manager;
    }

    /**
     * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
     * deploying minimal proxy contracts, also known as "clones".
     */
    function _clone(address implementation) internal returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }
}
