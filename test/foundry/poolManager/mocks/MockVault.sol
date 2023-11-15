// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

contract MockVault {
    address token0ReturnVal;
    address token1ReturnVal;

    function token0() external pure returns (address) {
        return address(0);
    }

    function token1() external pure returns (address) {
        return address(0);
    }

    function setToken0(address _token0) external {
        token0ReturnVal = _token0;
    }

    function setToken1(address _token1) external {
        token1ReturnVal = _token1;
    }
}
