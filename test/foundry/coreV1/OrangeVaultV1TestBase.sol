// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {OrangeParametersV1} from "../../../contracts/coreV1/OrangeParametersV1.sol";
import {UniswapV3LiquidityPoolManager} from "../../../contracts/poolManager/UniswapV3LiquidityPoolManager.sol";
import {AaveLendingPoolManager} from "../../../contracts/poolManager/AaveLendingPoolManager.sol";
import {OrangeVaultV1, IBalancerVault, IBalancerFlashLoanRecipient, IOrangeVaultV1, Errors, SafeERC20} from "../../../contracts/coreV1/OrangeVaultV1.sol";
import {OrangeStrategyImplV1} from "../../../contracts/coreV1/OrangeStrategyImplV1.sol";
import {OrangeStrategistV1} from "../../../contracts/coreV1/OrangeStrategistV1.sol";
import {IERC20} from "../../../contracts/libs/BalancerFlashloan.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IAaveV3Pool} from "../../../contracts/interfaces/IAaveV3Pool.sol";

import {TickMath} from "../../../contracts/libs/uniswap/TickMath.sol";
import {OracleLibrary} from "../../../contracts/libs/uniswap/OracleLibrary.sol";
import {FullMath, LiquidityAmounts} from "../../../contracts/libs/uniswap/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract OrangeVaultV1TestBase is BaseTest {
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.AaveAddr public aaveAddr;
    AddressHelper.UniswapAddr public uniswapAddr;
    AddressHelperV1.BalancerAddr public balancerAddr;

    OrangeVaultV1 public vault;
    IUniswapV3Pool public pool;
    ISwapRouter public router;
    IBalancerVault public balancer;
    IAaveV3Pool public aave;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public collateralToken0;
    IERC20 public debtToken1;
    OrangeParametersV1 public params;
    OrangeStrategyImplV1 public impl;
    OrangeStrategistV1 public strategist;

    int24 public lowerTick = -205680;
    int24 public upperTick = -203760;
    int24 public stoplossLowerTick = -206280;
    int24 public stoplossUpperTick = -203160;
    int24 public currentTick;

    // currentTick = -204714;

    function setUp() public virtual {
        (tokenAddr, aaveAddr, uniswapAddr) = AddressHelper.addresses(block.chainid);
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr500);
        aave = IAaveV3Pool(aaveAddr.poolAddr);
        collateralToken0 = IERC20(aaveAddr.awethAddr);
        debtToken1 = IERC20(aaveAddr.vDebtUsdcAddr);
        router = ISwapRouter(uniswapAddr.routerAddr);
        balancerAddr = AddressHelperV1.addresses(block.chainid);
        balancer = IBalancerVault(balancerAddr.vaultAddr);
        params = new OrangeParametersV1();

        params.setDepositCap(100_000 ether, 100_000 ether);
        params.setMinDepositAmount(1e16);
        params.setRouterFee(500);
        params.setRouter(address(router));
        params.setBalancer(address(balancer));
        params.setStrategist(address(this), true);
        params.setAllowlistEnabled(false);

        _deploy();
        _dealAndApprove();
    }

    function _deploy() internal virtual {
        //vault
        vault = new OrangeVaultV1(
            "OrangeVaultV1",
            "ORANGE_VAULT_V1",
            address(token0),
            address(token1),
            address(pool),
            address(aave),
            address(params)
        );

        //strategy impl
        impl = new OrangeStrategyImplV1();
        params.setStrategyImpl(address(impl));
        strategist = new OrangeStrategistV1(address(vault));
        params.setStrategist(address(strategist), true);
    }

    function _dealAndApprove() internal virtual {
        //set Ticks for testing
        (, int24 _tick, , , , , ) = pool.slot0();
        currentTick = _tick;

        //deal
        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        // deal(tokenAddr.usdcAddr, alice, 10_000_000 * 1e6);
        deal(tokenAddr.wethAddr, carol, 10_000 ether);
        deal(tokenAddr.usdcAddr, carol, 10_000_000 * 1e6);

        //approve
        token0.approve(address(vault), type(uint256).max);
        // vm.startPrank(alice);
        // token1.approve(address(vault), type(uint256).max);
        // vm.stopPrank();
        vm.startPrank(carol);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /* ========== TEST functions ========== */
    function swapByCarol(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        ISwapRouter.ExactInputSingleParams memory inputParams;
        if (_zeroForOne) {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: pool.fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        } else {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: pool.fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        }
        vm.prank(carol);
        amountOut_ = router.exactInputSingle(inputParams);
    }

    function multiSwapByCarol() internal {
        swapByCarol(true, 1 ether);
        swapByCarol(false, 2000 * 1e6);
        swapByCarol(true, 1 ether);
    }

    function consoleUnderlyingAssets() internal view {
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        console2.log("++++++++++++++++consoleUnderlyingAssets++++++++++++++++");
        console2.log(_underlyingAssets.liquidityAmount0, "liquidityAmount0");
        console2.log(_underlyingAssets.liquidityAmount1, "liquidityAmount1");
        console2.log(_underlyingAssets.accruedFees0, "accruedFees0");
        console2.log(_underlyingAssets.accruedFees1, "accruedFees1");
        console2.log(_underlyingAssets.vaultAmount0, "token0Balance");
        console2.log(_underlyingAssets.vaultAmount1, "token1Balance");
        console2.log("++++++++++++++++consoleUnderlyingAssets++++++++++++++++");
    }

    function consoleCurrentPosition() internal view {
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        console2.log("++++++++++++++++consoleCurrentPosition++++++++++++++++");
        console2.log(collateralToken0.balanceOf(address(vault.lendingPool())), "collateralToken0");
        console2.log(debtToken1.balanceOf(address(vault.lendingPool())), "debtToken1");
        console2.log(_underlyingAssets.liquidityAmount0, "liquidityAmount0");
        console2.log(_underlyingAssets.liquidityAmount1, "liquidityAmount1");
        console2.log("++++++++++++++++consoleCurrentPosition++++++++++++++++");
    }

    function _quoteEthPriceByTick(int24 _tick) internal view returns (uint256) {
        return OracleLibrary.getQuoteAtTick(_tick, 1 ether, address(token0), address(token1));
    }

    function roundTick(int24 _tick) internal view returns (int24) {
        return (_tick / pool.tickSpacing()) * pool.tickSpacing();
    }
}
