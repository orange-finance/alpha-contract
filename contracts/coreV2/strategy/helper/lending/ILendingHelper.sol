// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ILendingHelper {
    function balances(address pool, address token0, address token1) external view returns (uint256, uint256);

    function balanceOfCollateral(address pool, address token0) external view returns (uint256);

    function balanceOfDebt(address pool, address token1) external view returns (uint256);

    function supply(address pool, address token0, uint256 amount) external;

    function withdraw(address pool, address token0, uint256 amount) external;

    function borrow(address pool, address token1, uint256 amount) external;

    function repay(address pool, address token1, uint256 amount) external;
}
