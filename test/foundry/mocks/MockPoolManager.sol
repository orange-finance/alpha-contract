// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {Mock} from "@test/foundry/mocks/Mock.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";

contract MockPoolManager is Mock, IPoolManager {
    function setVault(address _vault) external mayRevert(IPoolManager.setVault.selector) {}
}
