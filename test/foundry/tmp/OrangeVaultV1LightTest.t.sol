// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {OrangeParametersV1} from "../../../contracts/coreV1/OrangeParametersV1.sol";
import {CamelotV3LiquidityPoolManager} from "../../../contracts/poolManager/CamelotV3LiquidityPoolManager.sol";
import {UniswapV3LiquidityPoolManager} from "../../../contracts/poolManager/UniswapV3LiquidityPoolManager.sol";
import {AaveLendingPoolManager} from "../../../contracts/poolManager/AaveLendingPoolManager.sol";
import {OrangeVaultV1, IBalancerVault, IOrangeVaultV1, ErrorsV1, SafeERC20} from "../../../contracts/coreV1/OrangeVaultV1.sol";
import {OrangeVaultV1Mock} from "../../../contracts/mocks/OrangeVaultV1Mock.sol";
import {OrangeStrategyImplV1Mock} from "../../../contracts/mocks/OrangeStrategyImplV1Mock.sol";
import {OrangeStrategyHelperV1} from "../../../contracts/coreV1/OrangeStrategyHelperV1.sol";
import {IERC20} from "../../../contracts/libs/BalancerFlashloan.sol";
import {IERC20Decimals} from "../../../contracts/coreV1/OrangeERC20.sol";

import {IAlgebraPool} from "../../../contracts/vendor/algebra/IAlgebraPool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IAaveV3Pool} from "../../../contracts/interfaces/IAaveV3Pool.sol";

import {TickMath} from "../../../contracts/libs/uniswap/TickMath.sol";
import {OracleLibrary} from "../../../contracts/libs/uniswap/OracleLibrary.sol";
import {FullMath, LiquidityAmounts} from "../../../contracts/libs/uniswap/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract OrangeVaultV1LightTest is BaseTest {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    /**** modify below ****/
    uint24 public constant FEE = 500;
    // uint256 constant INITIAL_BAL = 10_000 * 1e6;
    uint256 constant INITIAL_BAL = 10 ether;

    //uniswap
    // UniswapV3LiquidityPoolManager public liquidityPool;
    // IUniswapV3Pool public pool;
    //camelot
    CamelotV3LiquidityPoolManager public liquidityPool;
    IAlgebraPool public pool;

    //ARB - USDC.e
    // currentTick = -274999;
    // int24 public lowerTick = -275880;
    // int24 public upperTick = -274080;
    // int24 public stoplossLowerTick = -276780;
    // int24 public stoplossUpperTick = -273180;

    //ETH - USDC.e
    // int24 public lowerTick = -205680;
    // int24 public upperTick = -203760;
    // int24 public stoplossLowerTick = -206280;
    // int24 public stoplossUpperTick = -203160;

    //ETH - USDC at blocknum: 125971611
    // int24 public lowerTick = -205680;
    // int24 public upperTick = -203760;
    // int24 public stoplossLowerTick = -206280;
    // int24 public stoplossUpperTick = -203160;

    // ARB - ETH at blocknum: 125971611
    // current 74625
    int24 public lowerTick = 73740;
    int24 public upperTick = 75540;
    int24 public stoplossLowerTick = 72840;
    int24 public stoplossUpperTick = 76440;

    /**** modify end ****/

    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage
    uint256 constant HEDGE_RATIO = 100e6; //100%

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.AaveAddr public aaveAddr;
    AddressHelper.UniswapAddr public uniswapAddr;
    AddressHelperV1.BalancerAddr public balancerAddr;
    AddressHelperV2.CamelotAddr camelotAddr;
    AddressHelperV2.TokenAddrV2 tokenAddrV2;

    OrangeVaultV1Mock public vault;
    ISwapRouter public router;
    IBalancerVault public balancer;
    IAaveV3Pool public aave;
    IERC20 public token0;
    IERC20 public token1;
    OrangeParametersV1 public params;
    OrangeStrategyImplV1Mock public impl;
    AaveLendingPoolManager public lendingPool;
    OrangeStrategyHelperV1 public helper;
    int24 public currentTick;
    uint256 minDeposit;

    function setUp() public {
        _setAddresses();
        _deploy();
        _dealAndApprove();
    }

    function _setAddresses() internal virtual {
        (tokenAddr, aaveAddr, uniswapAddr) = AddressHelper.addresses(block.chainid);
        (tokenAddrV2, camelotAddr) = AddressHelperV2.addresses(block.chainid);

        /**** modify below ****/
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddrV2.arbAddr);
        // pool = IUniswapV3Pool(uniswapAddr.arbUsdcePoolAddr);
        pool = IAlgebraPool(camelotAddr.arbWethPoolAddr);
        /**** modify end ****/

        aave = IAaveV3Pool(aaveAddr.poolAddr);
        router = ISwapRouter(uniswapAddr.routerAddr);
        balancerAddr = AddressHelperV1.addresses(block.chainid);
        balancer = IBalancerVault(balancerAddr.vaultAddr);
        params = new OrangeParametersV1();

        params.setDepositCap(9_000 ether);
        minDeposit = (10 ** IERC20Decimals(address(token0)).decimals() / 100);
        params.setMinDepositAmount(minDeposit);
        params.setHelper(address(this));
        params.setAllowlistEnabled(false);
        params.setMaxLtv(70e6); // setting low maxLtv to avoid liquidation, because this test manipulate uniswap's price but doesn't aave's price
    }

    function _deploy() internal virtual {
        /**** modify below ****/
        // liquidityPool = new UniswapV3LiquidityPoolManager(address(token0), address(token1), address(pool));
        liquidityPool = new CamelotV3LiquidityPoolManager(address(token0), address(token1), address(pool));
        /**** modify end ****/
        lendingPool = new AaveLendingPoolManager(address(token0), address(token1), address(aave));
        //vault
        vault = new OrangeVaultV1Mock(
            "OrangeVaultV1Mock",
            "ORANGE_VAULT_V1",
            address(token0),
            address(token1),
            address(liquidityPool),
            address(lendingPool),
            address(params),
            address(router),
            FEE,
            address(balancer)
        );
        liquidityPool.setVault(address(vault));
        lendingPool.setVault(address(vault));

        impl = new OrangeStrategyImplV1Mock();
        params.setStrategyImpl(address(impl));
        helper = new OrangeStrategyHelperV1(address(vault));
        params.setHelper(address(helper));
        //set Ticks for testing
        currentTick = getCurrentTick();
    }

    function _dealAndApprove() internal virtual {
        //deal for tester
        deal(tokenAddrV2.arbAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000 ether);
        deal(tokenAddrV2.arbAddr, carol, 10_000 ether);
        deal(tokenAddr.usdcAddr, carol, 10_000 ether);
        //approve
        token0.approve(address(vault), type(uint256).max);
        vm.startPrank(carol);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();

        //deal for users
        deal(address(token0), address(11), INITIAL_BAL);
        deal(address(token0), address(12), INITIAL_BAL);
        deal(address(token0), address(13), INITIAL_BAL);
        deal(address(token0), address(14), INITIAL_BAL);
        deal(address(token0), address(15), INITIAL_BAL);

        //approve
        vm.prank(address(11));
        token0.approve(address(vault), type(uint256).max);
        vm.prank(address(12));
        token0.approve(address(vault), type(uint256).max);
        vm.prank(address(13));
        token0.approve(address(vault), type(uint256).max);
        vm.prank(address(14));
        token0.approve(address(vault), type(uint256).max);
        vm.prank(address(15));
        token0.approve(address(vault), type(uint256).max);
    }

    /* ========== TEST start ========== */
    //deposit and redeem
    function test_scenario1(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, minDeposit, INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, minDeposit, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, minDeposit, INITIAL_BAL);

        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //deposit, rebalance and redeem
    function test_scenario2(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, minDeposit, INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, minDeposit, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, minDeposit, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //deposit, rebalance, ChaigingPrice(InRange) and redeem
    function test_scenario3(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, minDeposit, INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, minDeposit, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, minDeposit, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Deposit, Rebalance, RisingPrice(OutOfRange), Stoploss, Rebalance and Redeem
    function test_scenario4(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, minDeposit, INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, minDeposit, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, minDeposit, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        int24 _tick = getCurrentTick();
        helper.stoploss(_tick);

        lowerTick = roundTick(_tick) - 900;
        upperTick = roundTick(_tick) + 900;
        _rebalance(HEDGE_RATIO);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Deposit, Rebalance, FallingPrice(OutOfRange), Stoploss, Rebalance and Redeem
    function test_scenario5(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        //if maxLtv is 80%, this case cause Aave error 36, COLLATERAL_CANNOT_COVER_NEW_BORROW
        //because the price Uniswap is changed, but Aaves' is not changed.
        params.setMaxLtv(70000000);

        _maxAsset1 = bound(_maxAsset1, minDeposit, INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, minDeposit, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, minDeposit, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(true, 1_000 ether); //current price under lowerPrice

        //stoploss
        console2.log("stoploss");
        int24 _tick = getCurrentTick();
        helper.stoploss(_tick);

        lowerTick = roundTick(_tick) - 900;
        upperTick = roundTick(_tick) + 900;
        _rebalance(HEDGE_RATIO);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Deposit, Rebalance, RisingPrice(OutOfRange), Stoploss, Rebalance, FallingPrice(OutOfRange), Stoploss, Rebalance, Redeem
    function test_scenario6(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, minDeposit, INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, minDeposit, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, minDeposit, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        int24 _tick = getCurrentTick();
        helper.stoploss(_tick);

        _tick = getCurrentTick();
        lowerTick = roundTick(_tick) - 900;
        upperTick = roundTick(_tick) + 900;
        _rebalance(HEDGE_RATIO);

        //swap
        console2.log("swap OutOfRange");
        swapByCarol(true, 1_000 ether); //current price under lowerPrice

        //stoploss
        console2.log("stoploss");
        _tick = getCurrentTick();
        helper.stoploss(_tick);

        _tick = getCurrentTick();
        lowerTick = roundTick(_tick) - 900;
        upperTick = roundTick(_tick) + 900;
        _rebalance(HEDGE_RATIO);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Fuzz testing
    //Deposit, Rebalance, RisingPrice, stoploss, Rebalance, FallingPRice, Rebalance
    function test_scenario7(
        uint _maxAsset1,
        uint _maxAsset2,
        uint _maxAsset3,
        uint _hedgeRatio,
        uint _randomLowerTick,
        uint _randomUpperTick
    ) public {
        // uint _maxAsset1 = 0;
        // uint _maxAsset2 = 0;
        // uint _maxAsset3 = 5628064358208601;
        // uint _hedgeRatio = 150e6;
        // uint _randomLowerTick = 0;
        // uint _randomUpperTick = 1e18;
        _maxAsset1 = bound(_maxAsset1, minDeposit, INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, minDeposit, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, minDeposit, INITIAL_BAL);
        _hedgeRatio = bound(_hedgeRatio, 20e6, 100e6);
        _randomLowerTick = bound(_randomLowerTick, 60, 900);
        _randomUpperTick = bound(_randomUpperTick, 60, 900);

        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(false, 500_000 * 1e6); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        int24 _tick = getCurrentTick();
        helper.stoploss(_tick);

        lowerTick = roundTick(_tick - int24(uint24(_randomLowerTick)));
        upperTick = roundTick(_tick + int24(uint24(_randomUpperTick)));
        _rebalance(_hedgeRatio);

        //swap
        console2.log("swap OutOfRange");
        swapByCarol(true, 400 ether); //current price under lowerPrice

        lowerTick = roundTick(_tick - int24(uint24(_randomLowerTick)));
        upperTick = roundTick(_tick + int24(uint24(_randomUpperTick)));
        _rebalance(_hedgeRatio);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    /* ========== TEST functions ========== */
    function swapByCarol(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        ISwapRouter.ExactInputSingleParams memory inputParams;
        if (_zeroForOne) {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: FEE,
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
                fee: FEE,
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

    function roundTick(int24 _tick) internal view returns (int24) {
        return (_tick / pool.tickSpacing()) * pool.tickSpacing();
    }

    function getCurrentTick() internal view returns (int24) {
        return liquidityPool.getCurrentTick();
    }

    function _deposit(
        uint _maxAsset1,
        uint _maxAsset2,
        uint _maxAsset3
    ) private returns (uint _share1, uint _share2, uint _share3) {
        console2.log("deposit11");
        vm.prank(address(11));
        _share1 = vault.deposit(_maxAsset1, _maxAsset1, new bytes32[](0));
        skip(1);

        console2.log("deposit12");
        _share2 = (vault.convertToShares(_maxAsset2) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(12));
        vault.deposit(_share2, _maxAsset2, new bytes32[](0));
        skip(1);

        console2.log("deposit13");
        _share3 = (vault.convertToShares(_maxAsset3) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(13));
        vault.deposit(_share3, _maxAsset3, new bytes32[](0));
        skip(1);

        skip(8 days);
    }

    function _redeem(
        uint _share1,
        uint _share2,
        uint _share3
    ) private returns (uint _minAsset1, uint _minAsset2, uint _minAsset3) {
        console2.log("redeem 11");
        _minAsset1 = (vault.convertToAssets(_share1) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(11));
        vault.redeem(_share1, _minAsset1);
        skip(1);

        console2.log("redeem 12");
        _minAsset2 = (vault.convertToAssets(_share2) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(12));
        vault.redeem(_share2, _minAsset2);
        skip(1);

        console2.log("redeem 13");
        _minAsset3 = (vault.convertToAssets(_share3) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(13));
        vault.redeem(_share3, _minAsset3);
        skip(1);
    }

    function _rebalance(uint _hedgeRatio) private {
        console2.log("rabalance");
        stoplossLowerTick = lowerTick - 600;
        stoplossUpperTick = upperTick + 600;
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 0);
        skip(1);
    }
}
