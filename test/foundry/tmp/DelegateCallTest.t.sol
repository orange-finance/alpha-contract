// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

contract DelegateCallTest is BaseTest {
    DelegateCaller caller;

    function setUp() public {
        address impl = address(new DelegateImpl());
        caller = new DelegateCaller(impl);
    }

    function testDelegateCall() public {
        caller.exec();
    }
}

contract DelegateImpl {
    function exec() external {
        console2.log(address(this));
        IDelegateCaller(address(this)).consoleHoge();
    }
}

interface IDelegateCaller {
    function consoleHoge() external;
}

contract DelegateCaller is Proxy, IDelegateCaller {
    address impl;
    uint counter = 100;

    function _implementation() internal view override returns (address) {
        return impl;
    }

    constructor(address _impl) {
        impl = _impl;
    }

    function consoleHoge() public {
        console2.log("hoge");
        console2.log(counter);
        counter++;
        console2.log(counter);
    }

    function exec() external {
        console2.log(address(this));
        _delegate(impl);
    }
}
