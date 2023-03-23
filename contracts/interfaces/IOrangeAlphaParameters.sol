// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

interface IOrangeAlphaParameters {
    function depositCap() external view returns (uint256 assets);

    function totalDepositCap() external view returns (uint256 assets);

    function minDepositAmount() external view returns (uint256 minDepositAmount);

    function slippageBPS() external view returns (uint16);

    function tickSlippageBPS() external view returns (uint24);

    function minAmountOutBPS() external view returns (uint16);

    function twapSlippageInterval() external view returns (uint32);

    function maxLtv() external view returns (uint32);

    function lockupPeriod() external view returns (uint40);

    function strategists(address) external view returns (bool);

    function allowlistEnabled() external view returns (bool);

    function merkleRoot() external view returns (bytes32);

    function gelato() external view returns (address);

    function periphery() external view returns (address);
}
