// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {GelatoOps, IOpsProxyFactory} from "../../../contracts/vendor/gelato/GelatoOps.sol";

contract GelatoOpsTest is BaseTest {
    GelatoOpsMock gelatoOps;
    address private constant OPS_PROXY_FACTORY =
        0xC815dB16D4be6ddf2685C201937905aBf338F5D7;
    address dedicatedMsgSender;

    function setUp() public {
        gelatoOps = new GelatoOpsMock();
        (dedicatedMsgSender, ) = IOpsProxyFactory(OPS_PROXY_FACTORY).getProxyOf(
            address(this)
        );
    }

    function testConstuctor() public {
        assertEq(gelatoOps.dedicatedMsgSender(), dedicatedMsgSender);
    }

    function testOnlyDedicatedMsgSender() public {
        vm.prank(dedicatedMsgSender);
        gelatoOps.exec();
    }

    function testRevertOnlyDedicatedMsgSender() public {
        vm.expectRevert("Only dedicated msg.sender");
        vm.prank(alice);
        gelatoOps.exec();
    }
}

contract GelatoOpsMock is GelatoOps {
    function exec() external onlyDedicatedMsgSender {}
}
