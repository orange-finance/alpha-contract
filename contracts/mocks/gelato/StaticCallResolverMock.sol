// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

// import {GelatoOps} from "../../libs/GelatoOps.sol";
import {StaticCallExecutorMock} from "./StaticCallExecutorMock.sol";

// import "forge-std/console2.sol";

contract StaticCallResolverMock {
    uint public count = 0;
    uint public lastTime = 0;
    StaticCallExecutorMock executor;

    constructor(address _exec) {
        executor = StaticCallExecutorMock(_exec);
    }

    // @inheritdoc IResolver
    function checker() external returns (bool, bytes memory) {
        //msg.sender must be address(0)
        require(msg.sender == address(0), "msg.sender != address(0)");

        //must be called at least 30 second apart
        if (block.timestamp - executor.lastTime() >= 30) {
            uint _count = executor.incrementCounter(0);

            // if (_count == 1) {
            //     return (false, bytes("1"));
            // } else if (_count == 2) {
            //     return (false, bytes("2"));
            // } else if (_count == 3) {
            //     return (false, bytes("3"));
            // } else if (_count == 4) {
            //     return (false, bytes("4"));
            // }
            bytes memory execPayload = abi.encodeWithSelector(StaticCallExecutorMock.incrementCounter.selector, _count);
            return (true, execPayload);
        } else {
            return (false, bytes("Error: too soon"));
        }
    }
}
