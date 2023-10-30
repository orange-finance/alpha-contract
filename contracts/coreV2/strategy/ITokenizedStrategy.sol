// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITokenizedStrategyState {
    function asset() external view returns (IERC20);
}

interface ITokenizedStrategyActions {
    function convertToShares(uint256 assets) external returns (uint256);

    function convertToAssets(uint256 shares) external returns (uint256);

    function deposit(uint256 assets, bytes calldata depositConfig) external returns (uint256 shares);

    function redeem(uint256 shares, bytes calldata redeemConfig) external returns (uint256 assets);

    function tend(bytes calldata tendConfig) external;
}

interface ITokenizedStrategy is ITokenizedStrategyState, ITokenizedStrategyActions, IERC20 {}
