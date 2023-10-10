// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

/**
 * @title PoolManager interface
 * @author Orange Finance
 */
interface IPoolManager {
    function setVault(address _vault) external;
}
