// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {GelatoOps, IOpsProxyFactory} from "../../../contracts/libs/GelatoOps.sol";
import {ARB_FORK_BLOCK_DEFAULT} from "../Config.sol";

contract GelatoOpsTest is BaseTest {
    GelatoOpsMock gelatoOps;
    address private constant OPS_PROXY_FACTORY = 0xC815dB16D4be6ddf2685C201937905aBf338F5D7;
    address dedicatedMsgSender;

    function setUp() public {
        vm.createSelectFork("arb", ARB_FORK_BLOCK_DEFAULT);
        gelatoOps = new GelatoOpsMock();
        (dedicatedMsgSender, ) = IOpsProxyFactory(OPS_PROXY_FACTORY).getProxyOf(address(this));
    }

    function test_getDedicatedMsgSender() public {
        assertEq(gelatoOps.getDedicatedMsgSender(address(this)), dedicatedMsgSender);
    }
}

contract GelatoOpsMock {
    function getDedicatedMsgSender(address msgSender) external view returns (address dedicatedMsgSender) {
        return GelatoOps.getDedicatedMsgSender(msgSender);
    }
}
