// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

import {IStrategy} from "@src/coreV2/vault/IStrategy.sol";
import {ITokenizedStrategy} from "@src/coreV2/strategy/ITokenizedStrategy.sol";

abstract contract BaseStrategy is IStrategy, Proxy {
    ITokenizedStrategy internal immutable Vault;

    address public immutable tokenizedStrategy;

    error OnlySelf();

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    constructor(address tokenizedStrategy_) {
        tokenizedStrategy = tokenizedStrategy_;

        Vault = ITokenizedStrategy(address(this));
    }

    function totalAssets() external view virtual override returns (uint256) {
        return 0;
    }

    function onDeposit(uint256 amount, bytes calldata depositConfig) external virtual onlySelf {
        _onDeposit(amount, depositConfig);
    }

    function onRedeem(uint256 amount, bytes calldata redeemConfig) external virtual onlySelf returns (uint256 assets) {
        return _onRedeem(amount, redeemConfig);
    }

    function _onDeposit(uint256 amount, bytes calldata depositConfig) internal virtual {}

    function _onRedeem(uint256 amount, bytes calldata redeemConfig) internal virtual returns (uint256 assets) {}

    function _implementation() internal view virtual override returns (address) {
        return tokenizedStrategy;
    }
}
