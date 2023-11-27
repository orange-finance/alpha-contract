// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {Fixture} from "@test/foundry/operation/factory/poolManagerDeployer/Fixture.sol";
import {IUniswapV3PoolImmutables} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {UniswapV3LiquidityPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/liquidityPool/UniswapV3.sol";
import {UniswapV3LiquidityPoolManager} from "@src/poolManager/UniswapV3LiquidityPoolManager.sol";

contract UniswapV3LiquidityPoolManagerDeployerTest is Fixture {
    function test_deployPoolManager__Success() public {
        _deployMockUniswapV3Pool();
        _deployMockTokens();

        bytes4 _sig = IUniswapV3PoolImmutables.fee.selector;
        uint24 _fee = 3000;
        mockUniswapV3Pool.setUint24ReturnValue(_sig, _fee);
        UniswapV3LiquidityPoolManagerDeployer _deployer = new UniswapV3LiquidityPoolManagerDeployer();

        address _manager = address(
            _deployer.deployPoolManager(address(mockToken0), address(mockToken1), address(mockUniswapV3Pool), "")
        );

        assertTrue(_manager != address(0), "should deploy UniswapV3LiquidityPoolManager");

        UniswapV3LiquidityPoolManager _m = UniswapV3LiquidityPoolManager(_manager);
        assertEq(address(_m.pool()), address(mockUniswapV3Pool), "should set pool");
        assertEq(_m.fee(), _fee, "should set fee");
    }

    function test_deployPoolManager__WithSetupData() public {
        _deployMockUniswapV3Pool();
        _deployMockTokens();

        bytes4 _sig = IUniswapV3PoolImmutables.fee.selector;
        uint24 _fee = 3000;
        mockUniswapV3Pool.setUint24ReturnValue(_sig, _fee);
        UniswapV3LiquidityPoolManagerDeployer _deployer = new UniswapV3LiquidityPoolManagerDeployer();

        bytes memory _setupData = abi.encode(
            UniswapV3LiquidityPoolManagerDeployer.PoolManagerConfig({
                owner: alice,
                perfFeeRecipient: bob,
                perfFeeDivisor: 10
            })
        );

        address _manager = address(
            _deployer.deployPoolManager(
                address(mockToken0),
                address(mockToken1),
                address(mockUniswapV3Pool),
                _setupData
            )
        );

        assertTrue(_manager != address(0), "should deploy UniswapV3LiquidityPoolManager");
        UniswapV3LiquidityPoolManager _m = UniswapV3LiquidityPoolManager(_manager);
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
