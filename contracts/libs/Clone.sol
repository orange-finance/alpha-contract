// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library Clone {
    /**
     * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
     * deploying minimal proxy contracts, also known as "clones".
     */
    function clone(address implementation) external returns (address instance) {
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
