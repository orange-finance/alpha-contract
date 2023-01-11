// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "./AddressHelper.sol";
import {Ints} from "../../../contracts/mocks/Ints.sol";

contract BaseTest is Test {
    using stdStorage for StdStorage;

    address alice = vm.addr(1);
    address bob = vm.addr(2);
    address carol = vm.addr(3);
    address david = vm.addr(4);

    function _setUp() internal virtual {
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(carol, "carol");
        vm.label(david, "david");
    }
}
