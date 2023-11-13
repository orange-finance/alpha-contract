// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.16;

import {IHandler} from "./IHandler.sol";

interface IUniswapV3SingleTickLiquidityHandler is IHandler {
    struct TokenIdInfo {
        uint128 totalLiquidity;
        uint128 totalSupply;
        uint128 liquidityUsed;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint64 lastDonation;
        uint128 donatedLiquidity;
        address token0;
        address token1;
        uint24 fee;
    }

    function tokenIds(uint256) external view returns (TokenIdInfo memory);

    function convertToShares(uint128 _liquidity) external view returns (uint256 shares);

    function convertToAssets(uint256 _shares) external view returns (uint128 liquidity);
}
