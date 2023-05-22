// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IOrangeParametersV1} from "./IOrangeParametersV1.sol";

// import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IOrangeBaseV1 {
    /* ========== VIEW FUNCTIONS ========== */

    function lowerTick() external view returns (int24);

    function upperTick() external view returns (int24);

    function token0() external view returns (IERC20 token0);

    function token1() external view returns (IERC20 token1);

    function liquidityPool() external view returns (address);

    function lendingPool() external view returns (address);

    function params() external view returns (IOrangeParametersV1);

    function hasPosition() external view returns (bool);
}
