// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ILendingPoolManager {
    function balances() external view returns (uint256, uint256);

    function balanceOfCollateral() external view returns (uint256);

    function balanceOfDebt() external view returns (uint256);

    function supply(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function borrow(uint256 amount) external;

    function repay(uint256 amount) external;
}
