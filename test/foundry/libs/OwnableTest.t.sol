// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {Ownable} from "../../../contracts/libs/Ownable.sol";

contract OwnableTest is BaseTest {
    OwnableMock ownable;

    function setUp() public {
        ownable = new OwnableMock();
    }

    function testConstuctor() public {
        assertEq(ownable.owner(), address(this));
    }

    function testOnlyOwner() public {
        ownable.exec();
    }

    function testRevertOnlyOwner() public {
        vm.expectRevert("Ownable");
        vm.prank(alice);
        ownable.checkOwner();

        vm.expectRevert("Ownable");
        vm.prank(alice);
        ownable.exec();
    }

    function testCheckOwner() public {
        ownable.checkOwner();
    }

    function testRevertCheckOwner() public {
        vm.expectRevert("Ownable");
        vm.prank(alice);
        ownable.checkOwner();
    }

    function testTransferOwnership() public {
        ownable.transferOwnership(alice);
        assertEq(ownable.owner(), alice);
    }

    function testRevertTransferOwnership() public {
        vm.expectRevert("Ownable");
        ownable.transferOwnership(address(0));
    }
}

contract OwnableMock is Ownable {
    function checkOwner() external view {
        return _checkOwner();
    }

    function exec() external onlyOwner {}
}
