// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Strings.sol)
// Our using oz library is v4.7.3 and equal function is not available.
// This function extracted from latest version as of 2023-10-03.
// We changed compiler version to ^0.8.0.

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
