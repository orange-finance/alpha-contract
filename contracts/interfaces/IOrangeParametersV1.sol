// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IOrangeParametersV1 {
    event SetSlippage(uint16 slippageBPS, uint24 tickSlippageBPS);
    event SetTwapSlippageInterval(uint32 twapSlippageInterval);
    event SetMaxLtv(uint32 maxLtv);
    event SetAllowlistEnabled(bool allowlistEnabled);
    event SetMerkleRoot(bytes32 merkleRoot);
    event SetDepositCap(uint256 depositCap);
    event SetMinDepositAmount(uint256 minDepositAmount);
    event SetHelper(address helper);
    event SetStrategyImpl(address strategyImpl);

    /// @notice Get the slippage tolerance
    function slippageBPS() external view returns (uint16);

    /// @notice Get the slippage tolerance of tick
    function tickSlippageBPS() external view returns (uint24);

    /// @notice Get the slippage interval of twap
    function twapSlippageInterval() external view returns (uint32);

    /// @notice Get the maximum LTV
    function maxLtv() external view returns (uint32);

    /// @notice Get true/false of allowlist
    function allowlistEnabled() external view returns (bool);

    /// @notice Get the merkle root
    function merkleRoot() external view returns (bytes32);

    /// @notice Get the total amount of USDC deposited by the user
    function depositCap() external view returns (uint256 assets);

    /// @notice Get the minimum amount of USDC to deposit at only initial deposit
    function minDepositAmount() external view returns (uint256 minDepositAmount);

    /// @notice Get true/false of strategist
    function helper() external view returns (address);

    /// @notice Get the strategy implementation contract
    function strategyImpl() external view returns (address);
}
