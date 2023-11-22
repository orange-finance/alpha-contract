// SPDX-License-Identifier: Unlicense

pragma solidity 0.8.16;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IHandler} from "./IHandler.sol";

interface IUniswapV3SingleTickLiquidityHandler is IHandler, IERC1155 {
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

    function convertToShares(uint128 liquidity, uint256 tokenId) external view returns (uint128 shares);

    function convertToAssets(uint128 shares, uint256 tokenId) external view returns (uint128 liquidity);
}
