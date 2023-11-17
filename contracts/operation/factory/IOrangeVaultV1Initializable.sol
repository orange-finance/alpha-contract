// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

/**
 * @title OrangeVaultV1 interface to initialize minimal-proxy clone vaults.
 * @author Orange Finance
 */
interface IOrangeVaultV1Initializable {
    struct VaultInitializeParams {
        string name;
        string symbol;
        address token0;
        address token1;
        address liquidityPoolManager;
        address lendingPoolManager;
        address params;
        address router;
        uint24 routerFee;
        address balancer;
    }

    /**
     * @notice Initializes the vault.
     * @param _params The parameters to initialize the vault.
     */
    function initialize(VaultInitializeParams calldata _params) external;
}
