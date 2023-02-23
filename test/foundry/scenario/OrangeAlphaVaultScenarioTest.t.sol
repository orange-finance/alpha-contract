// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";
import {OrangeAlphaVaultMock, IERC20} from "../../../contracts/mocks/OrangeAlphaVaultMock.sol";
import {IOpsProxyFactory} from "../../../contracts/libs/GelatoOps.sol";
import {OrangeAlphaParameters} from "../../../contracts/core/OrangeAlphaParameters.sol";

import {TickMath} from "../../../contracts/vendor/uniswap/TickMath.sol";
import {OracleLibrary} from "../../../contracts/vendor/uniswap/OracleLibrary.sol";
import {FullMath, LiquidityAmounts} from "../../../contracts/vendor/uniswap/LiquidityAmounts.sol";

contract OrangeAlphaVaultScenarioTest is BaseTest {
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;

    uint16 MAGIC_SCALE_1E4 = 10000; //for slippage

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;
    ISwapRouter router;

    OrangeAlphaVaultMock vault;
    OrangeAlphaParameters params;
    IUniswapV3Pool pool;
    IERC20 weth;
    IERC20 usdc;
    IERC20 debtToken0;
    IERC20 aToken1;
    int24 initialTick;

    int24 lowerTick = -205800;
    int24 upperTick = -203760;
    int24 stoplossLowerTick = -206280;
    int24 stoplossUpperTick = -203160;

    //parameters
    uint256 constant DEPOSIT_CAP = 10_000 * 1e6;
    uint256 constant TOTAL_DEPOSIT_CAP = 50_000 * 1e6;
    uint16 constant SLIPPAGE_BPS = 500;
    uint24 constant SLIPPAGE_TICK_BPS = 10;
    uint32 constant MAX_LTV = 70000000;
    uint32 constant LOCKUP_PERIOD = 7 days;

    function setUp() public {
        AddressHelper.AaveAddr memory aaveAddr;
        (tokenAddr, aaveAddr, uniswapAddr) = AddressHelper.addresses(
            block.chainid
        );

        router = ISwapRouter(uniswapAddr.routerAddr); //for test
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);
        debtToken0 = IERC20(aaveAddr.vDebtWethAddr);
        aToken1 = IERC20(aaveAddr.ausdcAddr);

        vault = new OrangeAlphaVaultMock(
            "OrangeAlphaVault",
            "ORANGE_ALPHA_VAULT",
            6,
            address(pool),
            address(weth),
            address(usdc),
            aaveAddr.poolAddr,
            aaveAddr.vDebtWethAddr,
            aaveAddr.ausdcAddr,
            address(params)
        );
        //set ticks
        vault.rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            1
        );

        //set parameters
        params.setDepositCap(DEPOSIT_CAP, TOTAL_DEPOSIT_CAP);
        params.setSlippage(SLIPPAGE_BPS, SLIPPAGE_TICK_BPS);
        params.setMaxLtv(MAX_LTV);
        params.setLockupPeriod(LOCKUP_PERIOD);
        params.setAllowlistEnabled(false); //merkle allow list off

        (, initialTick, , , , , ) = pool.slot0();
        console2.log(initialTick.toString(), "initialTick");

        //deal
        deal(tokenAddr.usdcAddr, address(11), 10_000 * 1e6);
        deal(tokenAddr.usdcAddr, address(12), 10_000 * 1e6);
        deal(tokenAddr.usdcAddr, address(13), 10_000 * 1e6);
        deal(tokenAddr.usdcAddr, address(14), 10_000 * 1e6);
        deal(tokenAddr.usdcAddr, address(15), 10_000 * 1e6);

        deal(tokenAddr.wethAddr, carol, 1000 ether);
        deal(tokenAddr.usdcAddr, carol, 100_000 * 1e6);

        //approve
        vm.prank(address(11));
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(address(12));
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(address(13));
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(address(14));
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(address(15));
        usdc.approve(address(vault), type(uint256).max);

        vm.startPrank(carol);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function test_scenario1() public {
        //deposit

        uint256 _shares1 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(11));
        vault.deposit(10_000 * 1e6, _shares1, new bytes32[](0));
        skip(1);
        uint256 _shares2 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(12));
        vault.deposit(10_000 * 1e6, _shares2, new bytes32[](0));
        skip(1);
        uint256 _shares3 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(13));
        vault.deposit(10_000 * 1e6, _shares3, new bytes32[](0));
        skip(1);
        uint256 _shares4 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(14));
        vault.deposit(10_000 * 1e6, _shares4, new bytes32[](0));
        skip(1);
        uint256 _shares5 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(15));
        vault.deposit(10_000 * 1e6, _shares5, new bytes32[](0));

        skip(8 days);

        //swap
        multiSwapByCarol(10 ether, 12_000 * 1e6, 100);

        //redeem
        redeem(address(11));
        skip(1);
        redeem(address(12));
        skip(1);
        redeem(address(13));
        skip(1);
        redeem(address(14));
        skip(1);
        redeem(address(15));

        (, int24 _tick, , , , , ) = pool.slot0();
        console2.log(_tick.toString(), "afterTick");
    }

    function test_scenario2() public {
        consoleRate();

        //deposit
        uint256 _shares1 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(11));
        vault.deposit(10_000 * 1e6, _shares1, new bytes32[](0));
        skip(1);
        uint256 _shares2 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(12));
        vault.deposit(10_000 * 1e6, _shares2, new bytes32[](0));
        skip(1);
        uint256 _shares3 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(13));
        vault.deposit(10_000 * 1e6, _shares3, new bytes32[](0));
        skip(1);
        uint256 _shares4 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(14));
        vault.deposit(10_000 * 1e6, _shares4, new bytes32[](0));
        skip(1);
        uint256 _shares5 = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vm.prank(address(15));
        vault.deposit(10_000 * 1e6, _shares5, new bytes32[](0));

        skip(8 days);

        //swap
        multiSwapByCarol(10 ether, 12_000 * 1e6, 100);

        //range out
        swapByCarol(true, 640 ether);
        skip(1 days);
        (, int24 __tick, , , , , ) = pool.slot0();
        console2.log(__tick.toString(), "middleTick");

        //stoploss
        vault.rebalance(lowerTick, upperTick, lowerTick, upperTick, 1);
        // vm.prank(vault.dedicatedMsgSender());
        vault.stoploss(__tick);
        skip(1 days);

        //rebalance
        int24 _newLowerTick = -207600;
        int24 _newUpperTick = -205560;
        // (, int24 ___tick, , , , , ) = pool.slot0();
        skip(1 days);
        vault.rebalance(
            _newLowerTick,
            _newUpperTick,
            _newLowerTick,
            _newUpperTick,
            2359131680723000
        );
        skip(1 days);

        //swap
        multiSwapByCarol(10 ether, 12_000 * 1e6, 100);

        //redeem
        redeem(address(11));
        skip(1);
        redeem(address(12));
        skip(1);
        redeem(address(13));
        skip(1);
        redeem(address(14));
        skip(1);
        redeem(address(15));

        (, int24 _tick, , , , , ) = pool.slot0();
        console2.log(_tick.toString(), "afterTick");
    }

    /* ========== TEST functions ========== */
    function redeem(address _user) private {
        uint256 _share11 = vault.balanceOf(_user);
        vm.prank(_user);
        vault.redeem(_share11, _user, address(0), 9_600 * 1e6);
        console2.log(usdc.balanceOf(_user), _user);
    }

    function swapByCarol(bool _zeroForOne, uint256 _amountIn)
        private
        returns (uint256 amountOut_)
    {
        ISwapRouter.ExactInputSingleParams memory params;
        if (_zeroForOne) {
            params = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                fee: 3000,
                recipient: carol,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        } else {
            params = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                fee: 3000,
                recipient: carol,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        }
        vm.prank(carol);
        amountOut_ = router.exactInputSingle(params);
    }

    function multiSwapByCarol(
        uint256 amountZeroForOne,
        uint256 amountOneForZero,
        uint8 times
    ) private {
        for (uint8 i = 0; i < times; i++) {
            swapByCarol(true, amountZeroForOne);
            swapByCarol(false, amountOneForZero);
        }
    }

    function consoleRate() private view {
        (, int24 _tick, , , , , ) = pool.slot0();
        uint256 rate0 = OracleLibrary.getQuoteAtTick(
            _tick,
            1 ether,
            address(weth),
            address(usdc)
        );
        console2.log(rate0, "rate");
    }
}
