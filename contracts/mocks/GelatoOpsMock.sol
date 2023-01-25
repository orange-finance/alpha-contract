// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GelatoOps} from "../vendor/gelato/GelatoOps.sol";

interface ICounter {
    function increaseCount(uint256 amount) external;
}

// solhint-disable not-rely-on-time
// solhint-disable no-empty-blocks
contract GelatoOpsMock is GelatoOps, ICounter {
    uint256 public count;
    uint256 public lastExecuted;

    function increaseCount(uint256 amount) external onlyDedicatedMsgSender {
        count += amount;
        lastExecuted = block.timestamp;
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        canExec = (block.timestamp - lastExecuted) > 180;

        execPayload = abi.encodeCall(ICounter.increaseCount, (1));
    }
}
