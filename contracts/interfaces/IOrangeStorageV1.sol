// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IOrangeParametersV1} from "./IOrangeParametersV1.sol";
import {IERC20} from "../libs/BalancerFlashloan.sol";

interface IOrangeStorageV1 {
    /* ========== VIEW FUNCTIONS ========== */

    function lowerTick() external view returns (int24);

    function upperTick() external view returns (int24);

    function token0() external view returns (IERC20 token0);

    function token1() external view returns (IERC20 token1);

    function liquidityPool() external view returns (address);

    function lendingPool() external view returns (address);

    function params() external view returns (IOrangeParametersV1);

    function hasPosition() external view returns (bool);

    /// @notice Get router fee
    function routerFee() external view returns (uint24);

    /// @notice Get the router contract
    function router() external view returns (address);

    /// @notice Get the balancer contract
    function balancer() external view returns (address);
}
