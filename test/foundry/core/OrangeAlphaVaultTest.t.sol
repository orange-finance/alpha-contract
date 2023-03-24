// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeAlphaTestBase.sol";
import "./IOrangeAlphaVaultEvent.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract OrangeAlphaVaultTest is OrangeAlphaTestBase, IOrangeAlphaVaultEvent {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    IOrangeAlphaVault.Ticks _ticks;

    // currentTick = -204714;

    uint256 constant HEDGE_RATIO = 100e6; //100%
    uint32 constant MAX_LTV = 70000000;

    function setUp() public override {
        super.setUp();

        params.setMaxLtv(MAX_LTV);
        _ticks.currentTick = currentTick;
        _ticks.lowerTick = lowerTick;
        _ticks.upperTick = upperTick;

        //rebalance (set ticks)
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
    }

    /* ========== MODIFIER ========== */
    function test_onlyPeriphery_Revert() public {
        vm.startPrank(alice);
        vm.expectRevert(bytes(Errors.ONLY_PERIPHERY));
        vault.deposit(0, address(this), 0);
        vm.expectRevert(bytes(Errors.ONLY_PERIPHERY));
        vault.redeem(0, address(this), address(0), 0);
    }

    /* ========== CONSTRUCTOR ========== */
    function test_constructor_Success() public {
        assertEq(vault.decimals(), IERC20Decimals(address(token1)).decimals());
        assertEq(address(vault.pool()), address(pool));
        assertEq(address(vault.token0()), address(token0));
        assertEq(address(vault.token1()), address(token1));
        assertEq(token0.allowance(address(vault), address(pool)), type(uint256).max);
        assertEq(token1.allowance(address(vault), address(pool)), type(uint256).max);
        assertEq(address(vault.aave()), address(aave));
        // assertEq(address(vault.debtToken0()), address(debtToken0));
        // assertEq(address(vault.aToken1()), address(aToken1));
        assertEq(token0.allowance(address(vault), address(aave)), type(uint256).max);
        assertEq(token1.allowance(address(vault), address(aave)), type(uint256).max);
        assertEq(address(vault.params()), address(params));
    }

    /* ========== VIEW FUNCTIONS ========== */
    function test_convertToShares_Success0() public {
        assertEq(vault.convertToShares(0), 0); //zero
    }

    function test_convertToShares_Success1() public {
        //assert shares after deposit
        uint256 _shares = vault.convertToShares(10_000 * 1e6);
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        assertEq(_shares, vault.convertToShares(10_000 * 1e6));
    }

    function test_convertToShares_Success2() public {
        uint256 _shares = vault.convertToShares(10_000 * 1e6);
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        assertApproxEqRel(10_000 * 1e6, _shares, 1e16);
    }

    function test_convertToAssets_Success0() public {
        assertEq(vault.convertToAssets(0), 0);
    }

    function test_convertToAssets_Success1() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        uint256 _shares = 2500 * 1e6;
        assertEq(vault.convertToAssets(_shares), _shares.mulDiv(vault.totalAssets(), vault.totalSupply()));
    }

    function test_convertToAssets_Success2() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        assertApproxEqRel(vault.convertToAssets(10_000 * 1e6), 10_000 * 1e6, 1e16);
    }

    function test_totalAssets_Success0() public {
        assertEq(vault.totalAssets(), 0);
    }

    function test_totalAssets_Success1() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        assertEq(vault.totalAssets(), 10_000 * 1e6);
    }

    function test_totalAssets_Success2() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        assertApproxEqRel(vault.totalAssets(), 10_000 * 1e6, 1e16);
    }

    function test_alignTotalAsset_Success0() public {
        //liquidityAmount0 == amount0Debt
        uint256 totalAlignedAssets = vault.alignTotalAsset(10 ether, 10000 * 1e6, 10 ether, 14000 * 1e6);
        // console2.log(totalAlignedAssets, "totalAlignedAssets");
        assertEq(totalAlignedAssets, 10000 * 1e6 + 14000 * 1e6);
    }

    function test_alignTotalAsset_Success1() public {
        //liquidityAmount0 < amount0Debt
        uint256 totalAlignedAssets = vault.alignTotalAsset(10 ether, 10000 * 1e6, 11 ether, 14000 * 1e6);
        // console2.log(totalAlignedAssets, "totalAlignedAssets");

        uint256 amount0deducted = 11 ether - 10 ether;
        amount0deducted = OracleLibrary.getQuoteAtTick(
            _ticks.currentTick,
            uint128(amount0deducted),
            address(token0),
            address(token1)
        );
        assertEq(totalAlignedAssets, 10000 * 1e6 + 14000 * 1e6 - amount0deducted);
    }

    function test_alignTotalAsset_Success2() public {
        //liquidityAmount0 > amount0Debt
        uint256 totalAlignedAssets = vault.alignTotalAsset(12 ether, 10000 * 1e6, 10 ether, 14000 * 1e6);
        // console2.log(totalAlignedAssets, "totalAlignedAssets");

        uint256 amount0Added = 12 ether - 10 ether;
        amount0Added = OracleLibrary.getQuoteAtTick(
            _ticks.currentTick,
            uint128(amount0Added),
            address(token0),
            address(token1)
        );
        assertEq(totalAlignedAssets, 10000 * 1e6 + 14000 * 1e6 + amount0Added);
    }

    function test_getUnderlyingBalances_Success0() public {
        //zero
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        assertEq(_underlyingAssets.liquidityAmount0, 0);
        assertEq(_underlyingAssets.liquidityAmount1, 0);
        assertEq(_underlyingAssets.accruedFees0, 0);
        assertEq(_underlyingAssets.accruedFees1, 0);
        assertEq(_underlyingAssets.token0Balance, 0);
        assertEq(_underlyingAssets.token1Balance, 0);
    }

    function test_getUnderlyingBalances_Success1() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        //zero
        assertGt(_underlyingAssets.liquidityAmount0, 0);
        assertGt(_underlyingAssets.liquidityAmount1, 0);
        //Greater than or equial 0
        assertGe(_underlyingAssets.token0Balance, 0);
        assertGe(_underlyingAssets.token1Balance, 0);
    }

    function test_getUnderlyingBalances_Success2() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

        multiSwapByCarol(); //swapped
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        //Greater than 0
        assertGt(_underlyingAssets.liquidityAmount0, 0);
        assertGt(_underlyingAssets.liquidityAmount1, 0);
        //Greater than 0
        assertGt(_underlyingAssets.accruedFees0, 0);
        assertGt(_underlyingAssets.accruedFees1, 0);
        //Greater than or equial 0
        assertGe(_underlyingAssets.token0Balance, 0);
        assertGe(_underlyingAssets.token1Balance, 0);
    }

    function test_computeTargetPositionByShares_Success() public {
        IOrangeAlphaVault.Positions memory _position = vault.computeTargetPositionByShares(
            100 ether,
            200 * 1e6,
            300 ether,
            400 * 1e6,
            25,
            100
        );
        assertEq(_position.debtAmount0, 100 ether / 4);
        assertEq(_position.collateralAmount1, (200 * 1e6) / 4);
        assertEq(_position.token0Balance, 300 ether / 4);
        assertEq(_position.token1Balance, (400 * 1e6) / 4);
    }

    //getRebalancedLiquidity is tested in OrangeAlphaRebalanceTest.t.sol

    //computeRebalancePosition is tested in OrangeAlphaComputeRebalancePositionTest.t.sol

    function test_getLtvByRange_Success1() public {
        uint256 _currentPrice = vault.quoteEthPriceByTick(_ticks.currentTick);
        uint256 _upperPrice = vault.quoteEthPriceByTick(stoplossUpperTick);
        uint256 ltv_ = uint256(MAX_LTV).mulDiv(_currentPrice, _upperPrice);
        assertEq(ltv_, vault.getLtvByRange(_ticks.currentTick, stoplossUpperTick));
    }

    function test_getLtvByRange_Success2() public {
        swapByCarol(true, 1000 ether); //current price under lowerPrice
        (, int24 _tick, , , , , ) = pool.slot0();
        uint256 _currentPrice = vault.quoteEthPriceByTick(_tick);
        uint256 _upperPrice = vault.quoteEthPriceByTick(stoplossUpperTick);
        // console2.log(_currentPrice, "_currentPrice");
        console2.log(_upperPrice, "_upperPrice");
        uint256 ltv_ = uint256(MAX_LTV).mulDiv(_currentPrice, _upperPrice);
        assertEq(ltv_, vault.getLtvByRange(_tick, stoplossUpperTick));
    }

    function test_getLtvByRange_Success3() public {
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice
        (, int24 _tick, , , , , ) = pool.slot0();
        console2.log(_tick.toString(), "_tick");
        assertEq(MAX_LTV, vault.getLtvByRange(_tick, -203500));
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    // deposit,_depositLiquidityByShares,_swapSurplusAmount are tested in OrangeAlphaVaultDepositTest.t.sol

    function test_redeem_Revert1() public {
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        vault.redeem(0, address(this), address(0), 9_900 * 1e6);
    }

    function test_redeem_Revert2() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        skip(1);
        vm.expectRevert(bytes(Errors.LESS_AMOUNT));
        vault.redeem(_shares, address(this), address(0), 100_900 * 1e6);
    }

    function test_redeem_Success0NoPosition() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        skip(8 days);

        uint256 _assets = (vault.convertToAssets(_shares) * 9900) / MAGIC_SCALE_1E4;
        uint256 _realAssets = vault.redeem(_shares, address(this), address(0), _assets);

        //assertion
        assertEq(10_000 * 1e6, _realAssets);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 10_000_000 * 1e6);
    }

    function test_redeem_Success1Max() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        skip(8 days);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        uint256 _assets = (vault.convertToAssets(_shares) * 9900) / MAGIC_SCALE_1E4;
        uint256 _realAssets = vault.redeem(_shares, address(this), address(0), _assets);
        //assertion
        assertApproxEqRel(_assets, _realAssets, 1e16);
        assertEq(vault.balanceOf(address(this)), 0);
        (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
        assertEq(_liquidity, 0);
        assertEq(debtToken0.balanceOf(address(vault)), 0);
        assertEq(aToken1.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertApproxEqRel(token1.balanceOf(address(this)), 10_000_000 * 1e6, 1e18);
    }

    function test_redeem_Success2Quater() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        skip(8 days);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        // prepare for assetion
        (uint128 _liquidity0, , , , ) = pool.positions(vault.getPositionID());
        uint256 _debtToken0 = debtToken0.balanceOf(address(vault));
        uint256 _aToken1 = aToken1.balanceOf(address(vault));

        //execute
        uint256 _assets = (vault.convertToAssets(_shares) * 9900) / MAGIC_SCALE_1E4;
        vault.redeem((_shares * 3) / 4, address(this), address(0), (_assets * 3) / 4);
        // assertion
        assertApproxEqRel(vault.balanceOf(address(this)), _shares / 4, 1e16);
        (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
        assertApproxEqRel(_liquidity, _liquidity0 / 4, 1e16);
        assertApproxEqRel(debtToken0.balanceOf(address(vault)), _debtToken0 / 4, 1e16);
        assertApproxEqRel(aToken1.balanceOf(address(vault)), _aToken1 / 4, 1e16);
        assertApproxEqRel(token1.balanceOf(address(this)), 9_997_500 * 1e6, 1e16);
    }

    function test_stoploss_Revert() public {
        vm.expectRevert(bytes(Errors.ONLY_STRATEGISTS_OR_GELATO));
        vm.prank(alice);
        vault.stoploss(1);
    }

    function test_stoploss_Success0ByGelato() public {
        vm.prank(params.gelatoExecutor());
        vault.stoploss(1);
    }

    function test_stoploss_Success1() public {
        vault.stoploss(_ticks.currentTick);
        IOrangeAlphaVault.Ticks memory __ticks = vault.getTicksByStorage();
        assertEq(__ticks.currentTick.getSqrtRatioAtTick(), _ticks.currentTick.getSqrtRatioAtTick());
        assertEq(__ticks.currentTick, _ticks.currentTick);
        assertEq(__ticks.lowerTick, _ticks.lowerTick);
        assertEq(__ticks.upperTick, _ticks.upperTick);
    }

    function test_stoploss_Success2WithoutPosition() public {
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        skip(1);
        (, int24 _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick);
        //assertion
        (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
        assertEq(_liquidity, 0);
        assertEq(debtToken0.balanceOf(address(vault)), 0);
        assertEq(aToken1.balanceOf(address(vault)), 0);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertApproxEqRel(token1.balanceOf(address(vault)), 10_000 * 1e6, 1e16);
    }

    function test_stoploss_Success3() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        skip(1);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        (, int24 _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick);
        skip(1);
        (, _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick);
        //assertion
        (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
        assertEq(_liquidity, 0);
        assertEq(debtToken0.balanceOf(address(vault)), 0);
        assertEq(aToken1.balanceOf(address(vault)), 0);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertApproxEqRel(token1.balanceOf(address(vault)), 10_000 * 1e6, 1e18);
    }

    // rebalance,_executeHedgeRebalance,_addLiquidityInRebalance are in OrangeAlphaRebalanceTest.t.sol

    function test_eventAction_Success() public {
        vm.expectEmit(false, false, false, false);
        emit Action(IOrangeAlphaVault.ActionType.MANUAL, address(this), 0, 0);
        vault.emitAction();
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    function assert_computeFeesEarned() internal {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(vault.getPositionID());

        uint256 accruedFees0 = vault.computeFeesEarned(true, feeGrowthInside0Last, liquidity) + uint256(tokensOwed0);
        uint256 accruedFees1 = vault.computeFeesEarned(false, feeGrowthInside1Last, liquidity) + uint256(tokensOwed1);
        console2.log(accruedFees0, "accruedFees0");
        console2.log(accruedFees1, "accruedFees1");

        // assert to fees collected acutually
        IOrangeAlphaVault.Ticks memory __ticks = vault.getTicksByStorage();
        uint256 _balance0Before = token0.balanceOf(address(vault));
        uint256 _balance1Before = token1.balanceOf(address(vault));
        (uint256 burn0_, uint256 burn1_) = vault.burnAndCollectFees(__ticks.lowerTick, __ticks.upperTick);
        uint256 _balance0After = token0.balanceOf(address(vault));
        uint256 _balance1After = token1.balanceOf(address(vault));
        assertEq(_balance0After - _balance0Before - burn0_, accruedFees0);
        assertEq(_balance1After - _balance1Before - burn1_, accruedFees1);
    }

    function test_computeFeesEarned_Success1() public {
        //current tick is in range

        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        skip(1);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);
        multiSwapByCarol(); //swapped

        (, int24 _tick, , , , , ) = pool.slot0();
        console2.log(_tick.toString(), "currentTick");
        assert_computeFeesEarned();
    }

    function test_computeFeesEarned_Success2UnderRange() public {
        vault.deposit(10_000 * 1e6, address(this), 9_900 * 1e6);
        skip(1);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);
        multiSwapByCarol(); //swapped

        swapByCarol(true, 1000 ether); //current price under lowerPrice
        // (, int24 __tick, , , , , ) = pool.slot0();
        // console2.log(__tick.toString(), "currentTick");
        assert_computeFeesEarned();
    }

    function test_computeFeesEarned_Success3OverRange() public {
        vault.deposit(10_000 * 1e6, address(this), 9_900 * 1e6);
        skip(1);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);
        multiSwapByCarol(); //swapped

        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice
        // (, int24 __tick, , , , , ) = pool.slot0();
        // console2.log(__tick.toString(), "currentTick");
        assert_computeFeesEarned();
    }

    function test_validateTicks_Success() public {
        vault.validateTicks(60, 120);
        vm.expectRevert(bytes(Errors.INVALID_TICKS));
        vault.validateTicks(120, 60);
        vm.expectRevert(bytes(Errors.INVALID_TICKS));
        vault.validateTicks(61, 120);
        vm.expectRevert(bytes(Errors.INVALID_TICKS));
        vault.validateTicks(60, 121);
    }

    function test_getTicksByStorage_Success() public {
        IOrangeAlphaVault.Ticks memory __ticks = vault.getTicksByStorage();
        assertEq(__ticks.currentTick.getSqrtRatioAtTick(), _ticks.currentTick.getSqrtRatioAtTick());
        assertEq(__ticks.currentTick, _ticks.currentTick);
        assertEq(__ticks.lowerTick, _ticks.lowerTick);
        assertEq(__ticks.upperTick, _ticks.upperTick);
    }

    function test_checkTickSlippage_Success1() public {
        vault.checkTickSlippage(0, 0);
        vm.expectRevert(bytes(Errors.HIGH_SLIPPAGE));
        vault.checkTickSlippage(10, 21);
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    function test_burnAndCollectFees_Success1WithoutPosition() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        skip(1);
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        (uint256 burn0_, uint256 burn1_) = vault.burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick);
        assertEq(_underlyingAssets.liquidityAmount0, burn0_);
        assertEq(_underlyingAssets.liquidityAmount1, burn1_);
    }

    function test_burnAndCollectFees_Success2() public {
        uint256 _shares = 10_000 * 1e6;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        skip(1);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        consoleUnderlyingAssets();
        (uint256 burn0_, uint256 burn1_) = vault.burnAndCollectFees(lowerTick, upperTick);
        assertApproxEqRel(_underlyingAssets.liquidityAmount0, burn0_, 1e16);
        assertApproxEqRel(_underlyingAssets.liquidityAmount1, burn1_, 1e16);
    }

    function test_swapAmountOut_Revert() public {
        vm.expectRevert(bytes(Errors.LACK_OF_TOKEN));
        vault.swapAmountOut(true, 10000 * 1e6, currentTick);

        vm.expectRevert(bytes(Errors.LACK_OF_TOKEN));
        vault.swapAmountOut(false, 10 ether, currentTick);
    }

    function test_swapAmountOut_Success0() public {
        token0.transfer(address(vault), 10 ether);
        vault.swapAmountOut(true, 10000 * 1e6, currentTick);
        assertApproxEqRel(token1.balanceOf(address(vault)), 10000 * 1e6, 5e16); //5%
    }

    function test_swapAmountOut_Success1() public {
        token1.transfer(address(vault), 10000 * 1e6);
        vault.swapAmountOut(false, 2 ether, currentTick);
        assertApproxEqRel(token0.balanceOf(address(vault)), 2 ether, 5e16); //5%
    }

    function test_swap_Success1() public {
        token0.transfer(address(vault), 10 ether);
        (uint256 _currentSqrtRatioX96, , , , , , ) = pool.slot0();
        uint _estimateAmount1 = OracleLibrary.getQuoteAtTick(
            _ticks.currentTick,
            10 ether,
            address(token0),
            address(token1)
        );
        vault.swap(true, 10 ether, _currentSqrtRatioX96);
        //assertion
        assertEq(token0.balanceOf(address(vault)), 0);
        assertApproxEqRel(token1.balanceOf(address(vault)), _estimateAmount1, 1e16);
    }

    function test_swap_Success2() public {
        token1.transfer(address(vault), 10000 * 1e6);
        (uint256 _currentSqrtRatioX96, , , , , , ) = pool.slot0();
        uint _estimateAmount0 = OracleLibrary.getQuoteAtTick(
            _ticks.currentTick,
            10000 * 1e6,
            address(token1),
            address(token0)
        );
        vault.swap(false, 10000 * 1e6, _currentSqrtRatioX96);
        //assertion
        assertEq(token1.balanceOf(address(vault)), 0);
        assertApproxEqRel(token0.balanceOf(address(vault)), _estimateAmount0, 1e16);
    }

    /* ========== CALLBACK FUNCTIONS ========== */
    function test_uniswapV3Callback_Revert() public {
        vm.expectRevert(bytes(Errors.ONLY_CALLBACK_CALLER));
        vault.uniswapV3MintCallback(0, 0, "");
        vm.expectRevert(bytes(Errors.ONLY_CALLBACK_CALLER));
        vault.uniswapV3SwapCallback(0, 0, "");
    }

    function test_uniswapV3MintCallback_Success() public {
        vm.prank(address(pool));
        vault.uniswapV3MintCallback(0, 0, "");
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);

        deal(address(token0), address(vault), 10 ether);
        deal(address(token1), address(vault), 10_000 * 1e6);
        vm.prank(address(pool));
        vault.uniswapV3MintCallback(1 ether, 1_000 * 1e6, "");
        assertEq(token0.balanceOf(address(vault)), 9 ether);
        assertEq(token1.balanceOf(address(vault)), 9_000 * 1e6);
    }

    function testuniswapV3SwapCallback_Success1() public {
        vm.prank(address(pool));
        vault.uniswapV3SwapCallback(0, 0, "");
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);

        deal(address(token0), address(vault), 10 ether);
        deal(address(token1), address(vault), 10_000 * 1e6);

        //amount0
        vm.prank(address(pool));
        vault.uniswapV3SwapCallback(1 ether, 0, "");
        assertEq(token0.balanceOf(address(vault)), 9 ether);
        assertEq(token1.balanceOf(address(vault)), 10_000 * 1e6);
        //amount1
        vm.prank(address(pool));
        vault.uniswapV3SwapCallback(0, 1_000 * 1e6, "");
        assertEq(token0.balanceOf(address(vault)), 9 ether);
        assertEq(token1.balanceOf(address(vault)), 9_000 * 1e6);
    }
}
