// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IOrangeVaultV1Initializable {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        address _liquidityPool,
        address _lendingPool,
        address _params,
        address _router,
        uint24 _routerFee,
        address _balancer
    ) external;
}
