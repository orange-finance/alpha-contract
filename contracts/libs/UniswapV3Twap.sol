// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

library UniswapV3Twap {
    function getTwap(IUniswapV3Pool _pool) external view returns (int24 avgTick) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = 5 minutes;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = _pool.observe(secondsAgo);

        require(tickCumulatives.length == 2, "array len");
        unchecked {
            avgTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(5 minutes)));
        }
    }
}
