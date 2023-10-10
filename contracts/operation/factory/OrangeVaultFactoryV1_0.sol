// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IOrangeVaultRegistry} from "@src/operation/registry/IOrangeVaultRegistry.sol";
import {IOrangeVaultV1Initializable} from "@src/operation/factory/IOrangeVaultV1Initializable.sol";
import {IPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/IPoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";
import {OrangeParametersV1} from "@src/coreV1/OrangeParametersV1.sol";
import {OrangeStrategyHelperV1} from "@src/coreV1/OrangeStrategyHelperV1.sol";
import {AddressZero} from "@src/operation/Errors.sol";

/**
 * @title OrangeVaultFactoryV1_0 contract
 * @author Orange Finance
 * @notice Factory contract for deploying new vaults.
 */
contract OrangeVaultFactoryV1_0 is AccessControlEnumerable {
    using Clones for address;

    address public immutable registry;
    address public immutable vaultImpl;
    address public strategyImpl;

    event VaultAdded(address indexed vault, string indexed version, address indexed parameters);
    event VaultRemoved(address indexed vault);

    struct VaultConfig {
        // when deploying a new vault
        string name;
        string symbol;
        address token0;
        address token1;
        address liquidityPool;
        address lendingPool;
        address router;
        uint24 routerFee;
        address balancer;
        // after deploying a new vault
        bool allowlistEnabled;
        uint256 depositCap;
        uint256 minDepositAmount;
        address owner;
        // TODO: check if we need to specify these params (default values are set in Vault's constructor)
        // uint16 slippageBPS;
        // uint24 tickSlippageBPS;
        // uint32 twapSlippageInterval;
        // uint32 maxLtv;
    }

    struct PoolManagerConfig {
        address managerDeployer;
        bytes setUpData;
    }

    struct StrategyConfig {
        address strategist;
    }

    constructor(address _registry, address _vaultImpl, address _strategyImpl) {
        if (_registry == address(0) || _vaultImpl == address(0) || _strategyImpl == address(0)) {
            revert AddressZero();
        }

        registry = _registry;
        vaultImpl = _vaultImpl;
        strategyImpl = _strategyImpl;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Deploy an new vault and perifery contracts for the vault. then add the vault to the registry.
     * @param _vaultConfig The configuration for the vault.
     * @param _liquidityManagerConfig The configuration for the liquidity pool manager.
     * @param _lendingManagerConfig The configuration for the lending pool manager.
     * @param _strategyConfig The configuration for the vault strategy.
     * @return The address of the new vault.
     */
    function createVault(
        VaultConfig calldata _vaultConfig,
        PoolManagerConfig calldata _liquidityManagerConfig,
        PoolManagerConfig calldata _lendingManagerConfig,
        StrategyConfig calldata _strategyConfig
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        // deploy parameters contract
        OrangeParametersV1 _parameters = new OrangeParametersV1();

        // deploy Liquidity / Lending Manager contract
        IPoolManager _liquidityManager = _deployPoolManager({
            _deployer: _liquidityManagerConfig.managerDeployer,
            _token0: _vaultConfig.token0,
            _token1: _vaultConfig.token1,
            _liquidityPool: _vaultConfig.liquidityPool,
            _setUpData: _liquidityManagerConfig.setUpData
        });

        IPoolManager _lendingManager = _deployPoolManager({
            _deployer: _lendingManagerConfig.managerDeployer,
            _token0: _vaultConfig.token0,
            _token1: _vaultConfig.token1,
            _liquidityPool: _vaultConfig.lendingPool,
            _setUpData: _lendingManagerConfig.setUpData
        });

        // deploy clone of vault contract
        // address _vault = _createClone(vaultImpl);
        address _vault = vaultImpl.clone();
        IOrangeVaultV1Initializable.VaultInitalizeParams memory _params = IOrangeVaultV1Initializable
            .VaultInitalizeParams({
                name: _vaultConfig.name,
                symbol: _vaultConfig.symbol,
                token0: _vaultConfig.token0,
                token1: _vaultConfig.token1,
                liquidityPool: _vaultConfig.liquidityPool,
                lendingPool: _vaultConfig.lendingPool,
                params: address(_parameters),
                router: _vaultConfig.router,
                routerFee: _vaultConfig.routerFee,
                balancer: _vaultConfig.balancer
            });

        IOrangeVaultV1Initializable(_vault).initialize(_params);

        // deploy strategy helper contract
        OrangeStrategyHelperV1 _strategyHelper = new OrangeStrategyHelperV1(_vault);
        _strategyHelper.setStrategist(_strategyConfig.strategist, true);

        // set parameters
        _parameters.setAllowlistEnabled(_vaultConfig.allowlistEnabled);
        _parameters.setDepositCap(_vaultConfig.depositCap);
        _parameters.setMinDepositAmount(_vaultConfig.minDepositAmount);
        _parameters.setHelper(address(_strategyHelper));
        _parameters.setStrategyImpl(strategyImpl);
        _parameters.transferOwnership(_vaultConfig.owner);

        // setup managers
        _lendingManager.setVault(_vault);
        _liquidityManager.setVault(_vault);

        return _vault;
    }

    function _deployPoolManager(
        address _deployer,
        address _token0,
        address _token1,
        address _liquidityPool,
        bytes calldata _setUpData
    ) internal returns (IPoolManager) {
        return
            IPoolManagerDeployer(_deployer).deployPoolManager({
                _token0: _token0,
                _token1: _token1,
                _liquidityPool: _liquidityPool,
                _setUpData: _setUpData
            });
    }
}
