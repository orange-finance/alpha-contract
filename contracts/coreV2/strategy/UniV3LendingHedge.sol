// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {BaseStrategy} from "@src/coreV2/strategy/BaseStrategy.sol";

contract UniV3LendingHedge is BaseStrategy {
    constructor(address tokenizedStrategyImpl) BaseStrategy(tokenizedStrategyImpl) {}

    function totalAssets() external view override returns (uint256) {}

    function _onDeposit(uint256 amount, bytes calldata depositConfig) internal override {}

    function _onRedeem(uint256 amount, bytes calldata redeemConfig) internal override returns (uint256 assets) {}

    function rebalance() external {}
}
