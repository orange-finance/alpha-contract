// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IProxy {
    /**
     * @notice initialize functions for proxy contracts.
     * @param  _params initilizing params
     * @param  _references initilizing addresses
     */
    function initialize(uint256[] calldata _params, address[] calldata _references) external;
}
