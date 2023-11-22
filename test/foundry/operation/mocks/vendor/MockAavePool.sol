// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {DataTypes} from "@src/vendor/aave/DataTypes.sol";
import {IAaveV3Pool} from "@src/interfaces/IAaveV3Pool.sol";

contract MockAaveV3Pool is IAaveV3Pool {
    // * NOTES: should be internal to avoid stack too deep error
    DataTypes.ReserveData internal _reserveDataReturnValue;

    function getReserveData(address) external view returns (DataTypes.ReserveData memory) {
        return _reserveDataReturnValue;
    }

    function supply(address, uint256, address, uint16) external pure {
        revert("Not implemented");
    }

    function withdraw(address, uint256, address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function borrow(address, uint256, uint256, uint16, address) external pure {
        revert("Not implemented");
    }

    function repay(address, uint256, uint256, address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function repayWithATokens(address, uint256, uint256) external pure returns (uint256) {
        revert("Not implemented");
    }

    function deposit(address, uint256, address, uint16) external pure {
        revert("Not implemented");
    }

    function getReserveNormalizedIncome(address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function getReserveNormalizedVariableDebt(address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function getUserAccountData(address) external pure returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        revert("Not implemented");
    }

    function flashLoanSimple(address, address, uint256, bytes calldata, uint16) external pure {
        revert("Not implemented");
    }

    function setReserveDataReturnValue(DataTypes.ReserveData calldata reserveDataReturnValue_) external {
        _reserveDataReturnValue = reserveDataReturnValue_;
    }
}
