// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

import "@test/foundry/operation/factory/v1_0/Fixture.sol";
import "@test/foundry/utils/ErrorUtil.sol";
import "@src/coreV1/proxy/OrangeVaultV1Initializable.sol";
import "@src/interfaces/IOrangeParametersV1.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract OrangeVaultFactoryV1_0Test is Fixture {
    function setUp() public {
        _setUp();
    }

    function test_createVault__Success() public {
        _deployFactory({_admin: alice});

        OrangeVaultFactoryV1_0.VaultConfig memory _vaultConfig = OrangeVaultFactoryV1_0.VaultConfig({
            version: "V1_DN_CLASSIC",
            name: "Orange Vault",
            symbol: "ORANGE",
            token0: address(mockToken0),
            token1: address(mockToken1),
            liquidityPool: address(0x1),
            lendingPool: address(0x2),
            router: address(0x5),
            routerFee: 3000,
            balancer: address(0x6),
            allowlistEnabled: true,
            depositCap: 100000,
            minDepositAmount: 100,
            owner: alice
        });

        OrangeVaultFactoryV1_0.PoolManagerConfig memory _liquidityManagerConfig = OrangeVaultFactoryV1_0
            .PoolManagerConfig({managerDeployer: address(mockLiquidityPoolManagerDeployer), setUpData: ""});

        OrangeVaultFactoryV1_0.PoolManagerConfig memory _lendingManagerConfig = OrangeVaultFactoryV1_0
            .PoolManagerConfig({managerDeployer: address(mockLendingPoolManagerDeployer), setUpData: ""});

        OrangeVaultFactoryV1_0.StrategyConfig memory _strategyConfig = OrangeVaultFactoryV1_0.StrategyConfig({
            strategist: bob
        });

        vm.prank(alice);
        OrangeVaultV1Initializable _vault = OrangeVaultV1Initializable(
            factory.createVault({
                _vaultConfig: _vaultConfig,
                _liquidityManagerConfig: _liquidityManagerConfig,
                _lendingManagerConfig: _lendingManagerConfig,
                _strategyConfig: _strategyConfig
            })
        );

        // check vault related values
        assertEq(_vault.name(), _vaultConfig.name, "name should be set");
        assertEq(_vault.symbol(), _vaultConfig.symbol, "symbol should be set");
        assertEq(address(_vault.token0()), _vaultConfig.token0, "token0 should be set");
        assertEq(address(_vault.token1()), _vaultConfig.token1, "token1 should be set");
        assertTrue(_vault.liquidityPool() != address(0), "liquidityPool should be set");
        assertTrue(_vault.lendingPool() != address(0), "lendingPool should be set");
        assertEq(_vault.router(), _vaultConfig.router, "router should be set");
        assertEq(_vault.routerFee(), _vaultConfig.routerFee, "routerFee should be set");
        assertEq(_vault.balancer(), _vaultConfig.balancer, "balancer should be set");

        IOrangeParametersV1 _params = _vault.params();

        // check parameter related values
        assertEq(_params.allowlistEnabled(), _vaultConfig.allowlistEnabled, "allowlistEnabled should be set");
        assertEq(_params.depositCap(), _vaultConfig.depositCap, "depositCap should be set");
        assertEq(_params.minDepositAmount(), _vaultConfig.minDepositAmount, "minDepositAmount should be set");
        assertEq(Ownable(address(_params)).owner(), _vaultConfig.owner, "owner should be set");
    }

    function test_createVault__Fail_NotFactoryAdmin() public {
        _deployFactory({_admin: alice});

        OrangeVaultFactoryV1_0.VaultConfig memory _vaultConfig = OrangeVaultFactoryV1_0.VaultConfig({
            version: "V1_DN_CLASSIC",
            name: "Orange Vault",
            symbol: "ORANGE",
            token0: address(mockToken0),
            token1: address(mockToken1),
            liquidityPool: address(0x1),
            lendingPool: address(0x2),
            router: address(0x5),
            routerFee: 3000,
            balancer: address(0x6),
            allowlistEnabled: true,
            depositCap: 100000,
            minDepositAmount: 100,
            owner: alice
        });

        OrangeVaultFactoryV1_0.PoolManagerConfig memory _liquidityManagerConfig = OrangeVaultFactoryV1_0
            .PoolManagerConfig({managerDeployer: address(mockLiquidityPoolManagerDeployer), setUpData: ""});

        OrangeVaultFactoryV1_0.PoolManagerConfig memory _lendingManagerConfig = OrangeVaultFactoryV1_0
            .PoolManagerConfig({managerDeployer: address(mockLendingPoolManagerDeployer), setUpData: ""});

        OrangeVaultFactoryV1_0.StrategyConfig memory _strategyConfig = OrangeVaultFactoryV1_0.StrategyConfig({
            strategist: bob
        });

        vm.prank(bob);
        vm.expectRevert(ErrorUtil.roleError(bob, 0x00));
        factory.createVault({
            _vaultConfig: _vaultConfig,
            _liquidityManagerConfig: _liquidityManagerConfig,
            _lendingManagerConfig: _lendingManagerConfig,
            _strategyConfig: _strategyConfig
        });
    }
}
