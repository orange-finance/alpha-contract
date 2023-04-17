// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

// import "forge-std/console2.sol";
import {GelatoOps} from "../../libs/GelatoOps.sol";

contract StaticCallExecutorMock {
    uint public count = 0;
    uint public lastTime = 0;
    address public gelatoExecutor;
    address public resolver;

    constructor() {
        gelatoExecutor = GelatoOps.getDedicatedMsgSender(msg.sender);
    }

    function setResolver(address _resolver) external {
        resolver = _resolver;
    }

    function incrementCounter(uint _minCount) external returns (uint256) {
        //require msg.sender == gelatoExecutor
        require(msg.sender == gelatoExecutor || msg.sender == resolver, "msg.sender is error");

        uint _count = count + 1;
        require(_count >= _minCount, "count < minCount");
        count = _count;
        lastTime = block.timestamp;
        return count;
    }
}
