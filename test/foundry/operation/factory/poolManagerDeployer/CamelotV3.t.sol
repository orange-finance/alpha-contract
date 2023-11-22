// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {Fixture} from "@test/foundry/operation/factory/poolManagerDeployer/Fixture.sol";
import {DataTypes} from "@src/vendor/aave/DataTypes.sol";
import {CamelotV3LiquidityPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/liquidityPool/CamelotV3.sol";
import {CamelotV3LiquidityPoolManager} from "@src/poolManager/CamelotV3LiquidityPoolManager.sol";

contract CamelotV3LiquidityPoolManagerDeployerTest is Fixture {
    function test_deployPoolManager__Success() public {
        _deployMockTokens();
        address _mockCamelotV3Pool = address(0x123);

        // bytes4 _sig = bytes4(keccak256("fee()"));
        CamelotV3LiquidityPoolManagerDeployer _deployer = new CamelotV3LiquidityPoolManagerDeployer();

        address _manager = address(
            _deployer.deployPoolManager(address(mockToken0), address(mockToken1), address(_mockCamelotV3Pool), "")
        );

        assertTrue(_manager != address(0), "should deploy CamelotV3LiquidityPoolManager");

        CamelotV3LiquidityPoolManager _m = CamelotV3LiquidityPoolManager(_manager);
        assertEq(address(_m.pool()), address(_mockCamelotV3Pool), "should set pool");
    }
}
