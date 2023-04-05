// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";

interface IOrangeAlphaPeriphery {
    /* ========== STRUCTS ========== */
    struct DepositType {
        uint256 assets;
        uint40 timestamp;
    }

    /* ========== VIEW FUNCTIONS ========== */
    /// @notice Get the total amount of USDC deposited by the user
    function deposits(address) external view returns (uint256 assets, uint40 timestamp);

    /// @notice Get the total amount of USDC deposited by all users
    function totalDeposits() external view returns (uint256);

    /// @notice Get the vault contract
    function vault() external view returns (IOrangeAlphaVault);

    /// @notice Get the parameters contract
    function params() external view returns (IOrangeAlphaParameters);

    /* ========== EXTERNAL FUNCTIONS ========== */

    /*
     * @notice Deposit USDC into the vault
     * @param _shares Amount of shares to mint
     * @param _maxAssets Maximum amount of USDC to deposit
     * @param merkleProof Merkle proof of the sender's allowlist status
     * @return Amount of USDC deposited
     */
    function deposit(uint256 _shares, uint256 _maxAssets, bytes32[] calldata merkleProof) external returns (uint256);

    /*
     * @notice Redeem USDC from the vault
     * @param _shares Amount of shares to redeem
     * @param _minAssets Minimum amount of USDC to redeem
     * @return Amount of USDC redeemed
     */
    function redeem(uint256 _shares, uint256 _minAssets) external returns (uint256);

    /*
     * @notice Redeem USDC from the vault by Flashloan
     * @param _shares Amount of shares to redeem
     * @param _minAssets Minimum amount of USDC to redeem
     * @return Amount of USDC redeemed
     */
    function flashRedeem(uint256 _shares, uint256 _minAssets) external returns (uint256);
}
