// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {TickMath} from "../vendor/uniswap/TickMath.sol";
import {IResolver} from "../vendor/gelato/IResolver.sol";
import {GelatoOps} from "../vendor/gelato/GelatoOps.sol";

contract GelatoMock is IResolver, GelatoOps {
    using TickMath for int24;

    bool public stoplossed;
    int24 public lowerTick;
    int24 public upperTick;
    int24 public currentTick;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        int24 _lowerTick,
        int24 _upperTick,
        int24 _currentTick
    ) {
        lowerTick = _lowerTick;
        upperTick = _upperTick;
        currentTick = _currentTick;
    }

    function checker()
        external
        view
        override
        returns (bool canExec, bytes memory execPayload)
    {
        if (canStoploss()) {
            execPayload = abi.encodeWithSelector(
                GelatoMock.stoploss.selector,
                currentTick + 1
            );
            return (true, execPayload);
        } else {
            return (false, bytes("in range"));
        }
    }

    function _isOutOfRange() internal view returns (bool) {
        return (currentTick > upperTick || currentTick < lowerTick);
    }

    function canStoploss() public view returns (bool) {
        return (!stoplossed && _isOutOfRange());
    }

    function stoploss(int24 _inputTick) external onlyDedicatedMsgSender {
        if (!canStoploss()) {
            revert("cannot stoploss");
        }
        stoplossed = true;
        currentTick = _inputTick;
    }

    function setCurrentTick(int24 _currentTick) external {
        currentTick = _currentTick;
    }

    function setTicks(int24 _lowerTick, int24 _upperTick) external {
        lowerTick = _lowerTick;
        upperTick = _upperTick;
    }

    function resetStoploss() external {
        stoplossed = false;
    }
}
