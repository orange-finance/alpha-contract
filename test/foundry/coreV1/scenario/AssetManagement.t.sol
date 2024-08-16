// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@test/foundry/coreV1/OrangeVaultV1Initializable/Fixture.t.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FullMath} from "@src/libs/uniswap/LiquidityAmounts.sol";
import {TickMath} from "@src/libs/uniswap/TickMath.sol";
import {ARB_FORK_BLOCK_DEFAULT} from "../../Config.sol";

contract AssetManagementScenarioTest is Fixture {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    uint256 constant HEDGE_RATIO = 100e6; //100%
    uint256 constant INITIAL_BAL = 10 ether;
    uint256 constant MIN_DEPOSIT = 1e15;

    function setUp() public override {
        vm.createSelectFork("arb", ARB_FORK_BLOCK_DEFAULT);

        super.setUp();
        params.setMaxLtv(70e6); // setting low maxLtv to avoid liquidation, because this test manipulate uniswap's price but doesn't aave's price

        //set Ticks for testing
        (, int24 _tick, , , , , ) = pool.slot0();
        currentTick = _tick;

        //deal

        deal(address(token0), address(11), INITIAL_BAL);
        deal(address(token0), address(12), INITIAL_BAL);
        deal(address(token0), address(13), INITIAL_BAL);
        deal(address(token0), address(14), INITIAL_BAL);
        deal(address(token0), address(15), INITIAL_BAL);

        deal(address(token0), carol, 1200 ether);
        deal(address(token1), carol, 1_200_000 * 1e6);

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

        vm.startPrank(carol);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    //joint test of vault, vault and parameters
    function test_scenario0() public {
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

        uint256 _maxAsset = 10 ether;
        vm.prank(address(11));
        uint _shares = vault.deposit(10 ether, _maxAsset, new bytes32[](0));
        skip(1);
        vm.prank(address(12));
        uint _shares2 = vault.deposit(10 ether, _maxAsset, new bytes32[](0));
        skip(1);

        assertEq(token0.balanceOf(address(11)), INITIAL_BAL - (10 ether));
        assertEq(token0.balanceOf(address(12)), INITIAL_BAL - (10 ether));
        assertEq(vault.balanceOf(address(11)), 10 ether - 1e15);
        assertEq(vault.balanceOf(address(12)), 10 ether);

        skip(7 days);

        uint256 _minAsset = 1 ether;
        vm.prank(address(11));
        vault.redeem(_shares, _minAsset);
        skip(1);
        vm.prank(address(12));
        vault.redeem(_shares2, _minAsset);
        skip(1);
        assertEq(token0.balanceOf(address(11)), INITIAL_BAL - 1e15);
        assertEq(token0.balanceOf(address(12)), INITIAL_BAL);
    }

    //deposit and redeem
    function test_scenario1(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);

        (uint _share1, uint _share2, uint _share3) = _deposit(_maxAsset1, _maxAsset2, _maxAsset3);

        (uint _minAsset1, uint _minAsset2, uint _minAsset3) = _redeem(_share1, _share2, _share3);

        assertGt(token0.balanceOf(address(11)), INITIAL_BAL - _maxAsset1 + _minAsset1);
        assertGt(token0.balanceOf(address(12)), INITIAL_BAL - _maxAsset2 + _minAsset2);
        assertGt(token0.balanceOf(address(13)), INITIAL_BAL - _maxAsset3 + _minAsset3);
    }

    //deposit, rebalance and redeem
    function test_scenario2(uint _maxAsset1, uint _maxAsset2, uint _maxAsset3) public {
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
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
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
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
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
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
        (, int24 _tick, , , , , ) = pool.slot0();
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

        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
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
        (, int24 _tick, , , , , ) = pool.slot0();
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
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
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
        (, int24 _tick, , , , , ) = pool.slot0();
        helper.stoploss(_tick);

        (, _tick, , , , , ) = pool.slot0();
        lowerTick = roundTick(_tick) - 900;
        upperTick = roundTick(_tick) + 900;
        _rebalance(HEDGE_RATIO);

        //swap
        console2.log("swap OutOfRange");
        swapByCarol(true, 1_000 ether); //current price under lowerPrice

        //stoploss
        console2.log("stoploss");
        (, _tick, , , , , ) = pool.slot0();
        helper.stoploss(_tick);

        (, _tick, , , , , ) = pool.slot0();
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
        _maxAsset1 = bound(_maxAsset1, params.minDepositAmount(), INITIAL_BAL);
        _maxAsset2 = bound(_maxAsset2, MIN_DEPOSIT, INITIAL_BAL);
        _maxAsset3 = bound(_maxAsset3, MIN_DEPOSIT, INITIAL_BAL);
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
        (, int24 _tick, , , , , ) = pool.slot0();
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
