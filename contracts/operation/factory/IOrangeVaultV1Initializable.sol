// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IOrangeVaultV1Initializable {
    struct VaultInitalizeParams {
        string name;
        string symbol;
        address token0;
        address token1;
        address liquidityPool;
        address lendingPool;
        address params;
        address router;
        uint24 routerFee;
        address balancer;
    }

    function initialize(VaultInitalizeParams calldata _params) external;
}
