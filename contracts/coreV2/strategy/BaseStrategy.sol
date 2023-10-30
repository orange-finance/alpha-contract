// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

import {IStrategy} from "@src/coreV2/vault/IStrategy.sol";
import {ITokenizedStrategy, ITokenizedStrategyActions} from "@src/coreV2/strategy/ITokenizedStrategy.sol";

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

    function depositCallback(uint256 share, bytes calldata depositConfig) external virtual onlySelf {
        _depositCallback(share, depositConfig);
    }

    function withdrawCallback(uint256 assets, bytes calldata redeemConfig) external virtual onlySelf {
        return _withdrawCallback(assets, redeemConfig);
    }

    function tendThis(bytes calldata tendConfig) external virtual onlySelf {
        _tend(tendConfig);
    }

    function tendTrigger() external view virtual returns (bool, bytes memory) {
        (bool _shouldTend, bytes memory _tendConfig) = _tendTrigger();

        if (!_shouldTend) return (_shouldTend, bytes("!shouldTend"));

        return (_shouldTend, abi.encodeWithSelector(ITokenizedStrategyActions.tend.selector, _tendConfig));
    }

    function _depositCallback(uint256 assets, bytes calldata depositConfig) internal virtual {}

    function _withdrawCallback(uint256 assets, bytes calldata redeemConfig) internal virtual {}

    function _tend(bytes calldata tendConfig) internal virtual {}

    function _tendTrigger() internal view virtual returns (bool, bytes memory) {
        return (false, "");
    }

    function _implementation() internal view virtual override returns (address) {
        return tokenizedStrategy;
    }
}
