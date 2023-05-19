// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

contract DelegateStorageTest is BaseTest {
    using Ints for int24;

    DelegateCaller caller;

    function setUp() public {
        address impl = address(new DelegateImpl());
        caller = new DelegateCaller(impl);
    }

    function testDelegateCall() public {
        caller.exec(150);
        console2.log(caller.counter());
        console2.log(caller.lowerTick().toString());
    }
}

contract DelegateImpl {
    int24 public lowerTick;
    int24 public upperTick;
    bool public hasPosition;
    bytes32 flashloanHash; //tempolary use in flashloan

    address impl;
    uint public counter;

    function exec(uint _y) external {
        console2.log(address(this));
        counter = _y;
        lowerTick = -100;
    }
}

contract DelegateCaller is Proxy {
    int24 public lowerTick;
    int24 public upperTick;
    bool public hasPosition;
    bytes32 flashloanHash; //tempolary use in flashloan

    address impl;
    uint public counter;

    function _implementation() internal view override returns (address) {
        return impl;
    }

    constructor(address _impl) {
        impl = _impl;
    }

    function exec(uint _y) external {
        console2.log(address(this));
        _delegate(impl);
    }
}
