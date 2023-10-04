// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {IOrangeVaultRegistry} from "@src/operation/registry/IOrangeVaultRegistry.sol";
import {IOrangeVaultV1Initializable} from "@src/operation/factory/IOrangeVaultV1Initializable.sol";
import {IPoolManagerDeployer} from "@src/operation/factory/poolManagerDeployer/IPoolManagerDeployer.sol";
import {IPoolManager} from "@src/operation/factory/poolManagerDeployer/IPoolManager.sol";
import {OrangeParametersV1} from "@src/coreV1/OrangeParametersV1.sol";
import {OrangeStrategyHelperV1} from "@src/coreV1/OrangeStrategyHelperV1.sol";
import {AddressZero} from "@src/operation/Errors.sol";

contract OrangeVaultFactoryV1_0 {
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
        address params;
        address router;
        uint24 routerFee;
        address balancer;
        // after deploying a new vault
        bool allowlistEnabled;
        uint256 depositCap;
        uint256 minDepositAmount;
        address owner;
        // TODO: check if we need to specify these params (defaut values are set in Vault's constructor)
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
    }

    function createVault(
        VaultConfig calldata _vaultConfig,
        PoolManagerConfig calldata _liquidityManagerConfig,
        PoolManagerConfig calldata _lendingManagerConfig,
        StrategyConfig calldata _strategyConfig
    ) external returns (address) {
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
        address _vault = _createClone(vaultImpl);
        IOrangeVaultV1Initializable(_vault).initialize({
            _name: _vaultConfig.name,
            _symbol: _vaultConfig.symbol,
            _token0: _vaultConfig.token0,
            _token1: _vaultConfig.token1,
            _liquidityPool: _vaultConfig.liquidityPool,
            _lendingPool: _vaultConfig.lendingPool,
            _params: address(_parameters),
            _router: _vaultConfig.router,
            _routerFee: _vaultConfig.routerFee,
            _balancer: _vaultConfig.balancer
        });

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

    /**
     * @notice Template Code for the create clone method:
     * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1167.md
     */
    function _createClone(address target) internal returns (address result) {
        //convert address to bytes20 for assembly use
        bytes20 targetBytes = bytes20(target);

        assembly {
            // allocate clone memory
            let clone := mload(0x40)
            // store initial portion of the delegation contract code in bytes form
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            // store the provided address
            mstore(add(clone, 0x14), targetBytes)
            // store the remaining delegation contract code
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            // create the actual delegate contract reference and return its address
            result := create(0, clone, 0x37)
        }

        require(result != address(0), "ERROR: ZERO_ADDRESS");
    }
}
