// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import {PoolManagerFactory, IOrangePoolManagerProxy} from "../../../contracts/poolManager/PoolManagerFactory.sol";
import {UniswapV3LiquidityPoolManager, IUniswapV3LiquidityPoolManager} from "../../../contracts/poolManager/UniswapV3LiquidityPoolManager.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TickMath} from "../../../contracts/libs/uniswap/TickMath.sol";
import {OracleLibrary} from "../../../contracts/libs/uniswap/OracleLibrary.sol";
import {FullMath, LiquidityAmounts} from "../../../contracts/libs/uniswap/LiquidityAmounts.sol";

contract PoolManagerFactoryTest is BaseTest {
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr public uniswapAddr;

    PoolManagerFactory public factory;
    UniswapV3LiquidityPoolManager public template;
    IUniswapV3LiquidityPoolManager public liquidityPool;
    IUniswapV3Pool public pool;
    ISwapRouter public router;
    IERC20 public token0;
    IERC20 public token1;

    int24 public lowerTick = -205680;
    int24 public upperTick = -203760;
    int24 public currentTick;

    // currentTick = -204714;

    function setUp() public virtual {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr500);
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);
        router = ISwapRouter(uniswapAddr.routerAddr);

        template = new UniswapV3LiquidityPoolManager();

        factory = new PoolManagerFactory();
        factory.approveTemplate(IOrangePoolManagerProxy(address(template)), true);

        //create proxy
        address[] memory _references = new address[](1);
        _references[0] = address(pool);
        liquidityPool = IUniswapV3LiquidityPoolManager(
            factory.create(
                address(template),
                address(this),
                address(token0),
                address(token1),
                new uint256[](0),
                _references
            )
        );

        //set Ticks for testing
        (, int24 _tick, , , , , ) = pool.slot0();
        currentTick = _tick;

        //deal
        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        deal(tokenAddr.wethAddr, carol, 10_000 ether);
        deal(tokenAddr.usdcAddr, carol, 10_000_000 * 1e6);

        //approve
        token0.approve(address(liquidityPool), type(uint256).max);
        token1.approve(address(liquidityPool), type(uint256).max);
        vm.startPrank(carol);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function test_mint_Success() public {
        _consoleBalance();

        //compute liquidity
        uint128 _liquidity = liquidityPool.getLiquidityForAmounts(lowerTick, upperTick, 1 ether, 1000 * 1e6);

        //mint
        (uint _amount0, uint _amount1) = liquidityPool.mint(lowerTick, upperTick, _liquidity);
        console2.log(_amount0, _amount1);

        //assertion of mint
        (uint _amount0_, uint _amount1_) = liquidityPool.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, _amount0_ + 1);
        assertEq(_amount1, _amount1_ + 1);

        uint128 _liquidity2 = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        console2.log(_liquidity2, "liquidity2");
        assertEq(_liquidity, _liquidity2);
        _consoleBalance();

        // burn and collect
        (uint burn0_, uint burn1_) = liquidityPool.burn(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, burn0_ + 1);
        assertEq(_amount1, burn1_ + 1);
        _consoleBalance();

        (uint collect0, uint collect1) = liquidityPool.collect(lowerTick, upperTick);
        console2.log(collect0, collect1);
        _consoleBalance();
    }

    function test_createByVault() public {
        //create vault
        address[] memory _references = new address[](1);
        _references[0] = address(pool);
        VaultMock _vault = new VaultMock(
            factory,
            address(template),
            address(token0),
            address(token1),
            new uint256[](0),
            _references
        );
        UniswapV3LiquidityPoolManager _liq = _vault.liquidityPool();
        assertEq(_liq.operator(), address(_vault));
    }

    /* ========== TEST functions ========== */
    function _consoleBalance() internal view {
        console2.log("balances: ");
        console2.log(
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this)),
            token0.balanceOf(address(liquidityPool)),
            token1.balanceOf(address(liquidityPool))
        );
    }
}

contract VaultMock {
    UniswapV3LiquidityPoolManager public liquidityPool;

    //in construcor, create liquidity pool by factory
    constructor(
        PoolManagerFactory _factory,
        address _template,
        address _token0,
        address _token1,
        uint256[] memory,
        address[] memory _references
    ) {
        address[] memory referencesNew = new address[](1);
        referencesNew[0] = _references[0];
        liquidityPool = UniswapV3LiquidityPoolManager(
            _factory.create(_template, address(this), _token0, _token1, new uint256[](0), _references)
        );
    }
}
