// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface IStrategy {
    function totalAssets() external view returns (uint256);

    function onDeposit(uint256 amount, bytes calldata depositConfig) external;

    function onRedeem(uint256 amount, bytes calldata redeemConfig) external returns (uint256 assets);
}
