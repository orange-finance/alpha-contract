// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeAlphaBase.sol";

import {Errors} from "../../../contracts/libs/Errors.sol";
import {TickMath} from "../../../contracts/vendor/uniswap/TickMath.sol";
import {OracleLibrary} from "../../../contracts/vendor/uniswap/OracleLibrary.sol";
import {FullMath, LiquidityAmounts} from "../../../contracts/vendor/uniswap/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract OrangeAlphaRebalanceTest is OrangeAlphaBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    // int24 public lowerTick = -205680;
    // int24 public upperTick = -203760;
    // int24 public stoplossLowerTick = -206280;
    // int24 public stoplossUpperTick = -203160;
    // currentTick = -204714;

    function test_rebalance_RevertTickSpacing() public {
        uint256 _hedgeRatio = 100e6;
        vm.expectRevert(bytes(Errors.INVALID_TICKS));
        vault.rebalance(
            -1,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );
        vm.expectRevert(bytes(Errors.INVALID_TICKS));
        vault.rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            -1,
            _hedgeRatio,
            1
        );
    }

    function test_rebalance_RevertNewLiquidity() public {
        uint256 _hedgeRatio = 100e6;
        //prepare
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;

        vault.deposit(10_000 * 1e6, address(this), _shares);

        uint128 _liquidity = vault.getRebalancedLiquidity(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        );

        vm.expectRevert(bytes(Errors.LESS_LIQUIDITY));
        vault.rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            _liquidity
        );
    }

    function test_rebalance_Success0() public {
        uint256 _hedgeRatio = 100e6;
        //totalSupply is zero
        int24 _newLowerTick = -207540;
        int24 _newUpperTick = -205680;
        int24 _newStoplossLowerTick = -208740;
        int24 _newStoplossUpperTick = -204480;
        vault.rebalance(
            _newLowerTick,
            _newUpperTick,
            _newStoplossLowerTick,
            _newStoplossUpperTick,
            _hedgeRatio,
            0
        );
        assertEq(vault.lowerTick(), _newLowerTick);
        assertEq(vault.upperTick(), _newUpperTick);
        assertEq(vault.stoplossLowerTick(), _newStoplossLowerTick);
        assertEq(vault.stoplossUpperTick(), _newStoplossUpperTick);
        assertEq(vault.stoplossed(), false);
    }

    function test_rebalance_Success1() public {
        uint256 _hedgeRatio = 100e6;
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vault.deposit(10_000 * 1e6, address(this), _shares);

        skip(1);

        //rebalance
        uint128 _liquidity = (vault.getRebalancedLiquidity(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        ) * 9900) / MAGIC_SCALE_1E4;
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            _liquidity
        );

        (uint128 _newLiquidity, , , , ) = pool.positions(vault.getPositionID());
        assertApproxEqRel(_liquidity, _newLiquidity, 1e16);

        assertEq(vault.stoplossed(), false);
        assertEq(vault.lowerTick(), lowerTick);
        assertEq(vault.upperTick(), upperTick);
        assertEq(vault.stoplossLowerTick(), stoplossLowerTick);
        assertEq(vault.stoplossUpperTick(), stoplossUpperTick);
    }

    function test_rebalance_Success2UnderRange() public {
        uint256 _hedgeRatio = 100e6;
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vault.deposit(10_000 * 1e6, address(this), _shares);

        skip(1);
        swapByCarol(true, 1000 ether); //current price under lowerPrice
        skip(1 days);

        //rebalance
        int24 _newLowerTick = -207540;
        int24 _newUpperTick = -205680;
        uint128 _liquidity = (vault.getRebalancedLiquidity(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        ) * 9900) / MAGIC_SCALE_1E4;
        _rebalance(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            _liquidity
        );

        (uint128 _newLiquidity, , , , ) = pool.positions(vault.getPositionID());
        assertApproxEqRel(_liquidity, _newLiquidity, 1e16);
    }

    function test_rebalance_Success3OverRange() public {
        uint256 _hedgeRatio = 100e6;
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vault.deposit(10_000 * 1e6, address(this), _shares);

        skip(1);
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice
        skip(1 days);

        //rebalance
        int24 _newLowerTick = -204600;
        int24 _newUpperTick = -202500;
        uint128 _liquidity = (vault.getRebalancedLiquidity(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        ) * 9900) / MAGIC_SCALE_1E4;
        _rebalance(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            _liquidity
        );

        (uint128 _newLiquidity, , , , ) = pool.positions(vault.getPositionID());
        assertApproxEqRel(_liquidity, _newLiquidity, 1e16);
    }

    //Supply and Borrow
    function test_rebalance_SuccessCase1() public {
        //deposit
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vault.deposit(_shares, address(this), 10_000 * 1e6);

        (, currentTick, , , , , ) = pool.slot0();
        uint256 _hedgeRatio = 100e6;
        _consoleComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            vault.getLtvByRange(currentTick, stoplossUpperTick),
            _hedgeRatio
        );

        skip(1);
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );
    }

    //Repay and Withdraw
    function test_rebalance_SuccessCase2() public {
        uint256 _hedgeRatio = 100e6;
        //deposit
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vault.deposit(_shares, address(this), 10_000 * 1e6);

        skip(1);
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );

        _hedgeRatio = 50e6;
        // (, currentTick, , , , , ) = pool.slot0();
        // _consoleComputePosition(
        //     10_000 * 1e6,
        //     currentTick,
        //     lowerTick,
        //     upperTick,
        //     vault.getLtvByRange(currentTick, stoplossUpperTick),
        //     _hedgeRatio
        // );
        // return;

        skip(1);
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );
    }

    //Repay and Supply
    function test_rebalance_SuccessCase3() public {
        uint256 _hedgeRatio = 100e6;
        //deposit
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vault.deposit(_shares, address(this), 10_000 * 1e6);

        skip(1);
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );

        // lowerTick = -205020;
        // int24 public lowerTick = -205680;
        // int24 public upperTick = -203760;
        // int24 public stoplossLowerTick = -206280;
        // int24 public stoplossUpperTick = -203160;
        // currentTick = -204714;

        _hedgeRatio = 100e6;
        // upperTick = -204000;
        // stoplossUpperTick = -203400;
        stoplossUpperTick = -201060;

        // (, currentTick, , , , , ) = pool.slot0();
        // _consoleComputePosition(
        //     10_000 * 1e6,
        //     currentTick,
        //     lowerTick,
        //     upperTick,
        //     vault.getLtvByRange(currentTick, stoplossUpperTick),
        //     _hedgeRatio
        // );
        // return;

        skip(1);
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );
    }

    //Borrow and Withdraw
    function test_rebalance_SuccessCase4() public {
        uint256 _hedgeRatio = 100e6;
        //deposit
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) /
            MAGIC_SCALE_1E4;
        vault.deposit(_shares, address(this), 10_000 * 1e6);

        skip(1);
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );

        _hedgeRatio = 115e6;
        upperTick = -204000;
        stoplossUpperTick = -203880;
        // (, currentTick, , , , , ) = pool.slot0();
        // _consoleComputePosition(
        //     10_000 * 1e6,
        //     currentTick,
        //     lowerTick,
        //     upperTick,
        //     vault.getLtvByRange(currentTick, stoplossUpperTick),
        //     _hedgeRatio
        // );
        // return;

        skip(1);
        _rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            1
        );
    }

    function _rebalance(
        int24 lowerTick,
        int24 upperTick,
        int24 stoplossLowerTick,
        int24 stoplossUpperTick,
        uint256 _hedgeRatio,
        uint128 _minNewLiquidity
    ) internal {
        uint _beforeAssets = vault.totalAssets();

        //rebalance
        vault.rebalance(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            _minNewLiquidity
        );

        // consoleUnderlyingAssets();
        consoleCurrentPosition();

        (, currentTick, , , , , ) = pool.slot0(); //retrieve current tick

        //assertions
        //ltv
        uint256 _ltv = vault.getLtvByRange(currentTick, stoplossUpperTick);
        uint256 _supply = aToken1.balanceOf(address(vault));
        uint256 _debt = debtToken0.balanceOf(address(vault));
        uint256 _debtUsdc = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(_debt),
            address(token0),
            address(token1)
        );
        uint256 _computedLtv = (_debtUsdc * MAGIC_SCALE_1E8) / _supply;
        // console.log("computedLtv", _computedLtv);
        // console.log("ltv", _ltv);
        assertApproxEqRel(_computedLtv, _ltv, 1e16);

        //hedge ratio
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault
            .getUnderlyingBalances();
        uint256 _hedgeRatioComputed = (_debt * MAGIC_SCALE_1E8) /
            _underlyingAssets.amount0Current;
        // console.log("hedgeRatioComputed", _hedgeRatioComputed);
        assertApproxEqRel(_hedgeRatioComputed, _hedgeRatio, 1e16);

        //total balance
        //after assets
        uint _afterAssets = vault.totalAssets();
        // console.log("beforeAssets", _beforeAssets);
        // console.log("afterAssets", _afterAssets);
        assertApproxEqRel(_afterAssets, _beforeAssets, 1e16);
    }

    function _consoleComputePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) private {
        IOrangeAlphaVault.Position memory _position = vault.computePosition(
            _assets,
            _currentTick,
            _lowerTick,
            _upperTick,
            _ltv,
            _hedgeRatio
        );
        console.log("++++++++ _consoleComputePosition ++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.supplyAmount1, "supplyAmount1");
        console.log(_position.addedAmount0, "addedAmount0");
        console.log(_position.addedAmount1, "addedAmount1");
    }
}