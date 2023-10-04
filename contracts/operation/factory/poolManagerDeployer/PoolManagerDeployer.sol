// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/IPoolManagerDeployer.sol";

abstract contract PoolManagerDeployer is IPoolManagerDeployer {
    function deployPoolManager(
        address _token0,
        address _token1,
        address _liquidityPool,
        bytes calldata _setUpData
    ) external virtual returns (address);

    function _onPoolManagerDeployed(
        address /* _poolManager */,
        address /* _token0 */,
        address /*_token1 */,
        address /*_liquidityPool */,
        bytes calldata /*_setUpData */
    ) internal virtual {
        revert("Not implemented");
    }
}
