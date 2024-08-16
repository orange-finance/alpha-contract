// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {Fixture} from "@test/foundry/operation/factory/poolManagerDeployer/Fixture.sol";
import {CamelotV3LiquidityPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/liquidityPool/CamelotV3.sol";
import {CamelotV3LiquidityPoolManager} from "@src/poolManager/CamelotV3LiquidityPoolManager.sol";

contract CamelotV3LiquidityPoolManagerDeployerTest is Fixture {
    function test_deployPoolManager__Success() public {
        _deployMockTokens();
        address _mockCamelotV3Pool = address(0x123);

        CamelotV3LiquidityPoolManagerDeployer _deployer = new CamelotV3LiquidityPoolManagerDeployer();

        address _manager = address(
            _deployer.deployPoolManager(address(mockToken0), address(mockToken1), address(_mockCamelotV3Pool), "")
        );

        assertTrue(_manager != address(0), "should deploy CamelotV3LiquidityPoolManager");

        CamelotV3LiquidityPoolManager _m = CamelotV3LiquidityPoolManager(_manager);
        assertEq(address(_m.pool()), address(_mockCamelotV3Pool), "should set pool");
    }

    function test_deployPoolManager__WithSetupData() public {
        _deployMockUniswapV3Pool();
        _deployMockTokens();

        address _mockCamelotV3Pool = address(0x123);
        CamelotV3LiquidityPoolManagerDeployer _deployer = new CamelotV3LiquidityPoolManagerDeployer();

        bytes memory _setupData = abi.encode(
            CamelotV3LiquidityPoolManagerDeployer.PoolManagerConfig({
                owner: alice,
                perfFeeRecipient: bob,
                perfFeeDivisor: 10
            })
        );

        address _manager = address(
            _deployer.deployPoolManager(
                address(mockToken0),
                address(mockToken1),
                address(_mockCamelotV3Pool),
                _setupData
            )
        );

        assertTrue(_manager != address(0), "should deploy CamelotV3LiquidityPoolManager");
        CamelotV3LiquidityPoolManager _m = CamelotV3LiquidityPoolManager(_manager);
        assertEq(_m.owner(), alice, "should set owner");
        assertEq(_m.perfFeeRecipient(), bob, "should set perfFeeRecipient");
        assertEq(_m.perfFeeDivisor(), 10, "should set perfFeeDivisor");

        vm.startPrank(alice);
        _m.setPerfFeeDivisor(20);
        _m.setPerfFeeRecipient(carol);
        vm.stopPrank();

        assertEq(_m.perfFeeDivisor(), 20, "should set perfFeeDivisor by new owner");
        assertEq(_m.perfFeeRecipient(), carol, "should set perfFeeRecipient by new owner");
    }
}
