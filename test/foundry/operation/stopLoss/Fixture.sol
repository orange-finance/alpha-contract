// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {OrangeStoplossChecker} from "../../../../contracts/operation/stoploss/OrangeStoplossChecker.sol";
import {MockStrategyHelperV1} from "./mocks/MockStrategyHelperV1.sol";

contract Fixture is Test {
    OrangeStoplossChecker public checker;

    event MockStoplossCalled(int24 _tick);

    function _deployChecker() internal {
        checker = new OrangeStoplossChecker();
    }

    function _deployMockHelpers(uint256 _count) internal {
        for (uint256 i = 0; i < _count; i++) {
            MockStrategyHelperV1 _helper = new MockStrategyHelperV1();
            checker.addVault(address(uint160(i + 100)), address(_helper));
        }
    }
}
