// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library ErrorUtil {
    function roleError(address _account, bytes32 _role) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(uint160(_account), 20),
                " is missing role ",
                Strings.toHexString(uint256(_role), 32)
            );
    }
}
