// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IOrangePoolManagerFactory {
    function create(
        address _implementation,
        address _operator,
        address _token0,
        address _token1,
        uint256[] calldata _params,
        address[] calldata _references
    ) external returns (address);
}
