// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";

/**
 * @title PoolManagerDeployer interface
 * @notice Interface for the PoolManagerDeployer contract.
 * @dev All Deployer contracts should follow this interface to ensure compatibility with the factory.
 */
interface IPoolManagerDeployer {
    /**
     * @notice Deploy a pool manager contract
     * @param _token0 Token 0 address
     * @param _token1 Token 1 address
     * @param _liquidityPool Liquidity pool address
     * @param _setUpData additional setup data for backwords compatibility
     */
    function deployPoolManager(
        address _token0,
        address _token1,
        address _liquidityPool,
        bytes calldata _setUpData
    ) external returns (IPoolManager);
}
