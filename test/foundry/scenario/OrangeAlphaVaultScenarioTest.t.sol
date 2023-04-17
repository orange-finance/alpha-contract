// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../core/OrangeAlphaTestBase.sol";
import {OrangeAlphaPeriphery, IOrangeAlphaPeriphery} from "../../../contracts/core/OrangeAlphaPeriphery.sol";

contract OrangeAlphaVaultScenarioTest is OrangeAlphaTestBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    IOrangeAlphaVault.Ticks _ticks;
    IOrangeAlphaPeriphery periphery;

    // currentTick = -204714;

    uint256 constant HEDGE_RATIO = 100e6; //100%
    uint256 constant INITIAL_BAL = 100_000 * 1e6;
    uint256 constant MIN_DEPOSIT = 10 * 1e6;

    function _setUpParams() internal override {
        periphery = new OrangeAlphaPeriphery(address(vault), address(params));
        //set parameters
        params.setPeriphery(address(periphery));
        params.setAllowlistEnabled(false);

        //set Ticks for testing
        (, int24 _tick, , , , , ) = pool.slot0();
        currentTick = _tick;

        //deal

        deal(address(token1), address(11), INITIAL_BAL);
        deal(address(token1), address(12), INITIAL_BAL);
        deal(address(token1), address(13), INITIAL_BAL);
        deal(address(token1), address(14), INITIAL_BAL);
        deal(address(token1), address(15), INITIAL_BAL);

        deal(address(token0), carol, 1200 ether);
        deal(address(token1), carol, 1_200_000 * 1e6);

        //approve
        vm.prank(address(11));
        token1.approve(address(periphery), type(uint256).max);
        vm.prank(address(12));
        token1.approve(address(periphery), type(uint256).max);
        vm.prank(address(13));
        token1.approve(address(periphery), type(uint256).max);
        vm.prank(address(14));
        token1.approve(address(periphery), type(uint256).max);
        vm.prank(address(15));
        token1.approve(address(periphery), type(uint256).max);

        vm.startPrank(carol);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    //joint test of vault, periphery and parameters
    function test_scenario0() public {
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

        uint256 _shares = 10_000 * 1e6;
        uint256 _maxAsset = 10_000 * 1e6;
        vm.prank(address(11));
        periphery.deposit(_shares, _maxAsset, new bytes32[](0));
        skip(1);
        vm.prank(address(12));
        periphery.deposit(_shares, _maxAsset, new bytes32[](0));
        skip(1);

        assertEq(token1.balanceOf(address(11)), INITIAL_BAL - (10_000 * 1e6));
        assertEq(token1.balanceOf(address(12)), INITIAL_BAL - (10_000 * 1e6));
        assertEq(vault.balanceOf(address(11)), 10_000 * 1e6);
        assertEq(vault.balanceOf(address(12)), 10_000 * 1e6);

        skip(7 days);

        uint256 _minAsset = 1_000 * 1e6;
        vm.prank(address(11));
        periphery.redeem(_shares, _minAsset);
        skip(1);
        vm.prank(address(12));
        periphery.redeem(_shares, _minAsset);
        skip(1);
        assertEq(token1.balanceOf(address(11)), INITIAL_BAL);
        assertEq(token1.balanceOf(address(12)), INITIAL_BAL);
    }

    //deposit and redeem
    function test_scenario1(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);

        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token1.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token1.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token1.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //deposit, rebalance and redeem
    function test_scenario2(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token1.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token1.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token1.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //deposit, rebalance, ChaigingPrice(InRange) and redeem
    function test_scenario3(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token1.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token1.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token1.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Deposit, Rebalance, RisingPrice(OutOfRange), Stoploss, Rebalance and Redeem
    function test_scenario4(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        (, int24 _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick, (vault.totalAssets() * 9900) / 10000);

        _rebalance(_tick);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token1.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token1.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token1.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Deposit, Rebalance, FallingPrice(OutOfRange), Stoploss, Rebalance and Redeem
    function test_scenario5(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        //if maxLtv is 80%, this case cause Aave error 36, COLLATERAL_CANNOT_COVER_NEW_BORROW
        //because the price Uniswap is changed, but Aaves' is not changed.
        params.setMaxLtv(70000000);

        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(true, 1_000 ether); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        (, int24 _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick, (vault.totalAssets() * 9900) / 10000);

        _rebalance(_tick);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token1.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token1.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token1.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Deposit, Rebalance, RisingPrice(OutOfRange), Stoploss, Rebalance, FallingPrice(OutOfRange), Stoploss, Rebalance, Redeem
    function test_scenario6(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        (, int24 _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick, (vault.totalAssets() * 9900) / 10000);

        _rebalance(_tick);

        //swap
        console2.log("swap OutOfRange");
        swapByCarol(true, 1_000 ether); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        (, _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick, (vault.totalAssets() * 9900) / 10000);

        _rebalance(_tick);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token1.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token1.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token1.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //Flash testing
    //Deposit, Rebalance, RisingPrice(OutOfRange), stoploss, Rebalance and FlashRedeem
    function test_scenario8(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        //swap
        console2.log("swap");
        multiSwapByCarol();

        console2.log("swap OutOfRange");
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice

        //stoploss
        console2.log("stoploss");
        (, int24 _tick, , , , , ) = pool.slot0();
        vault.stoploss(_tick, (vault.totalAssets() * 9900) / 10000);

        _rebalance(_tick);

        console2.log("flash redeem 11");
        uint _minAsset1 = (vault.convertToAssets(_share1) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(11));
        periphery.redeem(_share1, _minAsset1);
        skip(1);

        console2.log("flash redeem 12");
        uint _minAsset2 = (vault.convertToAssets(_share2) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(12));
        periphery.redeem(_share2, _minAsset2);
        skip(1);

        console2.log("flash redeem 13");
        uint _minAsset3 = (vault.convertToAssets(_share3) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(13));
        periphery.redeem(_share3, _minAsset3);
        skip(1);

        assertGt(token1.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token1.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token1.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    /* ========== TEST functions ========== */
    function _deposit(
        uint _maxAsset1,
        uint _maxAsset2,
        uint _maxAsset3
    ) private returns (uint _share1, uint _share2, uint _share3) {
        console2.log("deposit11");
        _share1 = _maxAsset1;
        vm.prank(address(11));
        periphery.deposit(_share1, _maxAsset1, new bytes32[](0));
        skip(1);

        console2.log("deposit12");
        _share2 = (vault.convertToShares(_maxAsset2) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(12));
        periphery.deposit(_share2, _maxAsset2, new bytes32[](0));
        skip(1);

        console2.log("deposit13");
        _share3 = (vault.convertToShares(_maxAsset3) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(13));
        periphery.deposit(_share3, _maxAsset3, new bytes32[](0));
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
        periphery.redeem(_share1, _minAsset1);
        skip(1);

        console2.log("redeem 12");
        _minAsset2 = (vault.convertToAssets(_share2) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(12));
        periphery.redeem(_share2, _minAsset2);
        skip(1);

        console2.log("redeem 13");
        _minAsset3 = (vault.convertToAssets(_share3) * 9900) / MAGIC_SCALE_1E4;
        vm.prank(address(13));
        periphery.redeem(_share3, _minAsset3);
        skip(1);
    }

    function _rebalance(int24 _currentTick) private {
        console2.log("rabalance");
        int24 _roundedTick = roundTick(_currentTick);
        lowerTick = _roundedTick - 900;
        upperTick = _roundedTick + 900;
        stoplossLowerTick = _roundedTick - 1500;
        stoplossUpperTick = _roundedTick + 1500;
        uint128 _liquidity = (vault.getRebalancedLiquidity(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            HEDGE_RATIO
        ) * 9900) / MAGIC_SCALE_1E4;
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, _liquidity);
        skip(1);
    }

    // function redeem(address _user) private {
    //     uint256 _share11 = vault.balanceOf(_user);
    //     vm.prank(_user);
    //     periphery.redeem(_share11, _user, address(0), 9_600 * 1e6);
    //     console2.log(token1.balanceOf(_user), _user);
    // }

    // function consoleRate() private view {
    //     (, int24 _tick, , , , , ) = pool.slot0();
    //     uint256 rate0 = OracleLibrary.getQuoteAtTick(_tick, 1 ether, address(token0), address(token1));
    //     console2.log(rate0, "rate");
    // }
}
