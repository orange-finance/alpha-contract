// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {PoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/PoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";
import {StubLendingPoolManager} from "@src/poolManager/StubLendingPoolManager.sol";

contract StubLendingPoolManagerDeployer is PoolManagerDeployer {
    function deployPoolManager(address, address, address, bytes calldata) external override returns (IPoolManager) {
        return new StubLendingPoolManager();
    }
}
