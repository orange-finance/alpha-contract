// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/Strings.sol";

library Ints {
    using Strings for uint256;

    function toString(int256 _value) public pure returns (string memory) {
        if (_value >= 0) {
            return uint256(_value).toString();
        } else {
            uint256 _valueUint = uint256(_value * -1);
            return string(abi.encodePacked("-", _valueUint.toString()));
        }
    }
}
