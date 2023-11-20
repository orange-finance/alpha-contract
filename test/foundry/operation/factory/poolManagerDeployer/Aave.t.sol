// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import {Fixture} from "@test/foundry/operation/factory/poolManagerDeployer/Fixture.sol";
import {DataTypes} from "@src/vendor/aave/DataTypes.sol";
import {AaveLendingPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/lendingPool/Aave.sol";
import {AaveLendingPoolManager} from "@src/poolManager/AaveLendingPoolManager.sol";

contract AaveLendingPoolManagerDeployerTest is Fixture {
    function test_deployPoolManager__Success() public {
        _deployMockAaveV3Pool();
        _deployMockTokens();

        DataTypes.ReserveConfigurationMap memory _configuration = DataTypes.ReserveConfigurationMap({data: 0});
        DataTypes.ReserveData memory _reserveData = DataTypes.ReserveData({
            configuration: _configuration,
            liquidityIndex: 0,
            currentLiquidityRate: 0,
            variableBorrowIndex: 0,
            currentVariableBorrowRate: 0,
            currentStableBorrowRate: 0,
            lastUpdateTimestamp: 0,
            id: 0,
            aTokenAddress: address(mockToken0),
            stableDebtTokenAddress: address(0),
            variableDebtTokenAddress: address(mockToken1),
            interestRateStrategyAddress: address(0),
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });

        mockAaveV3Pool.setReserveDataReturnValue(_reserveData);
        AaveLendingPoolManagerDeployer _deployer = new AaveLendingPoolManagerDeployer();

        address _manager = address(
            _deployer.deployPoolManager(address(mockToken0), address(mockToken1), address(mockAaveV3Pool), "")
        );

        assertTrue(_manager != address(0), "should deploy AaveLendingPoolManager");

        AaveLendingPoolManager _m = AaveLendingPoolManager(_manager);
        assertEq(address(_m.aave()), address(mockAaveV3Pool), "should set aave");
        assertEq(address(_m.token0()), address(mockToken0), "should set token0");
        assertEq(address(_m.token1()), address(mockToken1), "should set token1");
    }
}
