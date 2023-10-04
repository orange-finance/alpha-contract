// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Mock} from "@test/foundry/mocks/Mock.sol";

contract MockUniswapV3Pool is Mock {
    function fee() external view mayRevert(MockUniswapV3Pool.fee.selector) returns (uint24) {
        return uint24Returns[MockUniswapV3Pool.fee.selector];
    }
}
