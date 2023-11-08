// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import "./Fixture.sol";
import {IResolver} from "../../../../contracts/interfaces/IResolver.sol";

contract OrangeStopLossCheckerTest is Fixture {
    function test_getVaultCount__Success() public {
        _deployChecker();
        _deployMockHelpers(5);

        assertEq(checker.getVaultCount(), 5);
    }

    function test_checker__Success() public {
        _deployChecker();
        _deployMockHelpers(3);
        checker.grantRole(checker.BATCH_CALLER(), address(this));

        address _v1 = checker.getVaultAt(0);
        address _v2 = checker.getVaultAt(1);
        address _v3 = checker.getVaultAt(2);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setCanExec(true);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setCanExec(true);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setCanExec(true);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setTick(1);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setTick(2);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setTick(3);

        address[] memory _targets = new address[](3);
        _targets[0] = _v1;
        _targets[1] = _v2;
        _targets[2] = _v3;

        bytes memory _payload1 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v1))).stoploss.selector,
            1
        );
        bytes memory _payload2 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v2))).stoploss.selector,
            2
        );
        bytes memory _payload3 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v3))).stoploss.selector,
            3
        );

        bytes[] memory _payloads = new bytes[](3);
        _payloads[0] = _payload1;
        _payloads[1] = _payload2;
        _payloads[2] = _payload3;

        (bool _canExec, bytes memory _execPayload) = checker.checker();

        assertEq(_canExec, true);
        assertEq(_execPayload, abi.encodeWithSelector(checker.stoplossBatch.selector, _targets, _payloads));

        vm.expectEmit(true, true, true, true);
        emit MockStoplossCalled(1);
        vm.expectEmit(true, true, true, true);
        emit MockStoplossCalled(2);
        vm.expectEmit(true, true, true, true);
        emit MockStoplossCalled(3);

        (bool _ok, ) = address(checker).call(_execPayload);
        assertTrue(_ok);
    }

    function test_checker__Success_Call2ndHelper() public {
        _deployChecker();
        _deployMockHelpers(3);
        checker.grantRole(checker.BATCH_CALLER(), address(this));

        address _v1 = checker.getVaultAt(0);
        address _v2 = checker.getVaultAt(1);
        address _v3 = checker.getVaultAt(2);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setCanExec(false);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setCanExec(true);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setCanExec(false);

        MockStrategyHelperV1(address(checker.helpers(_v2))).setTick(2);

        address[] memory _targets = new address[](3);
        _targets[0] = _v2;

        bytes memory _payload1 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v2))).stoploss.selector,
            2
        );

        bytes[] memory _payloads = new bytes[](3);
        _payloads[0] = _payload1;

        (bool _canExec, bytes memory _execPayload) = checker.checker();
        assertEq(_canExec, true);
        assertEq(_execPayload, abi.encodeWithSelector(checker.stoplossBatch.selector, _targets, _payloads));

        vm.expectEmit(true, true, true, true);
        emit MockStoplossCalled(2);

        (bool _ok, ) = address(checker).call(_execPayload);
        assertTrue(_ok);
    }

    function test_removeVault__Success() public {
        _deployChecker();
        _deployMockHelpers(3);
        checker.grantRole(checker.BATCH_CALLER(), address(this));

        address _v1 = checker.getVaultAt(0);
        address _v2 = checker.getVaultAt(1);
        address _v3 = checker.getVaultAt(2);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setCanExec(true);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setCanExec(true);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setCanExec(true);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setTick(1);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setTick(2);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setTick(3);

        checker.removeVault(_v1);
        checker.removeVault(_v3);

        // check if vaults are removed
        assertEq(checker.getVaultCount(), 1);
        assertEq(checker.getVaultAt(0), _v2);
        vm.expectRevert(stdError.indexOOBError);
        checker.getVaultAt(1);
        vm.expectRevert(stdError.indexOOBError);
        checker.getVaultAt(2);

        // check if helpers are removed
        assertEq(address(checker.helpers(_v1)), address(0));
        assertEq(address(checker.helpers(_v3)), address(0));

        // check if checker works as expected
        address[] memory _targets = new address[](1);
        _targets[0] = _v2;

        bytes memory _payload1 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v2))).stoploss.selector,
            2
        );
        bytes[] memory _payloads = new bytes[](1);
        _payloads[0] = _payload1;

        (bool _canExec, bytes memory _execPayload) = checker.checker();

        assertEq(_canExec, true);
        assertEq(_execPayload, abi.encodeWithSelector(checker.stoplossBatch.selector, _targets, _payloads));

        vm.expectEmit(true, true, true, true);
        emit MockStoplossCalled(2);

        (bool _ok, ) = address(checker).call(_execPayload);
        assertTrue(_ok);
    }

    function test_checker__Fail_NoVaultExecutable() public {
        _deployChecker();
        _deployMockHelpers(3);

        address _v1 = checker.getVaultAt(0);
        address _v2 = checker.getVaultAt(1);
        address _v3 = checker.getVaultAt(2);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setCanExec(false);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setCanExec(false);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setCanExec(false);

        (bool _canExec, bytes memory _execPayload) = checker.checker();
        assertEq(_canExec, false);
        assertEq(_execPayload, bytes("OrangeStopLossChecker: No vaults to stoploss"));
    }

    function test_checker__Fail_NoVaultAdded() public {
        _deployChecker();

        (bool _canExec, bytes memory _execPayload) = checker.checker();
        assertEq(_canExec, false);
        assertEq(_execPayload, bytes("OrangeStopLossChecker: No vaults to stoploss"));
    }

    function test_checker__Fail_NotBatchCaller() public {
        _deployChecker();
        _deployMockHelpers(3);
        checker.grantRole(checker.BATCH_CALLER(), address(this));

        address _v1 = checker.getVaultAt(0);
        address _v2 = checker.getVaultAt(1);
        address _v3 = checker.getVaultAt(2);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setCanExec(true);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setCanExec(true);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setCanExec(true);

        MockStrategyHelperV1(address(checker.helpers(_v1))).setTick(1);
        MockStrategyHelperV1(address(checker.helpers(_v2))).setTick(2);
        MockStrategyHelperV1(address(checker.helpers(_v3))).setTick(3);

        address[] memory _targets = new address[](3);
        _targets[0] = _v1;
        _targets[1] = _v2;
        _targets[2] = _v3;

        bytes memory _payload1 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v1))).stoploss.selector,
            1
        );
        bytes memory _payload2 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v2))).stoploss.selector,
            2
        );
        bytes memory _payload3 = abi.encodeWithSelector(
            MockStrategyHelperV1(address(checker.helpers(_v3))).stoploss.selector,
            3
        );

        bytes[] memory _payloads = new bytes[](3);
        _payloads[0] = _payload1;
        _payloads[1] = _payload2;
        _payloads[2] = _payload3;

        (bool _canExec, bytes memory _execPayload) = checker.checker();

        assertEq(_canExec, true);
        assertEq(_execPayload, abi.encodeWithSelector(checker.stoplossBatch.selector, _targets, _payloads));

        vm.expectRevert();
        (bool _ok, ) = address(checker).call(_execPayload);
        assertFalse(_ok);
    }
}
