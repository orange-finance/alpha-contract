// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {Mock} from "@test/foundry/mocks/Mock.sol";
import {IPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/IPoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";

contract MockPoolManagerDeployer is Mock, IPoolManagerDeployer {
    address public poolManagerReturnValue;

    function deployPoolManager(
        address,
        address,
        address,
        bytes calldata
    ) external view mayRevert(IPoolManagerDeployer.deployPoolManager.selector) returns (IPoolManager) {
        return IPoolManager(poolManagerReturnValue);
    }

    function setPoolManagerReturnValue(address _poolManager) public {
        poolManagerReturnValue = _poolManager;
    }
}
