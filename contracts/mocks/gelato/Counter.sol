// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// import "forge-std/console2.sol";
import {GelatoOps} from "../../libs/GelatoOps.sol";

// solhint-disable not-rely-on-time
// solhint-disable no-empty-blocks
contract Counter {
    uint256 public count;
    uint256 public lastExecuted;
    address public gelatoExecutor;

    constructor() {
        gelatoExecutor = GelatoOps.getDedicatedMsgSender(msg.sender);
    }

    function increaseCount(uint256 amount) external {
        require(msg.sender == gelatoExecutor, "msg.sender != gelatoExecutor");

        count += amount;
        lastExecuted = block.timestamp;
    }
}
