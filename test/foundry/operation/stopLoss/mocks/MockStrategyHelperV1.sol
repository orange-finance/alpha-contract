// SPDX-License-Identifier: UNLICENCED

pragma solidity 0.8.16;

contract MockStrategyHelperV1 {
    bytes public constant CHECKER_FAILED = bytes("MockStrategyHelperV1: Checker failed");
    bool public canExec = true;
    int24 public tick;

    event MockStoplossCalled(int24 _tick);

    function setCanExec(bool _canExec) external {
        canExec = _canExec;
    }

    function setTick(int24 _tick) external {
        tick = _tick;
    }

    function checker() external view returns (bool, bytes memory) {
        if (canExec) return (true, abi.encodeWithSelector(this.stoploss.selector, tick));

        return (false, CHECKER_FAILED);
    }

    function stoploss(int24 _tick) external {
        emit MockStoplossCalled(_tick);
        // do nothing
    }
}
