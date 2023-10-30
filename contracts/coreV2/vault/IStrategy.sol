// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface IStrategy {
    function totalAssets() external view returns (uint256);

    function depositCallback(uint256 assets, bytes calldata depositConfig) external;

    function withdrawCallback(uint256 assets, bytes calldata redeemConfig) external;

    function tendThis(bytes calldata tendConfig) external;
}
