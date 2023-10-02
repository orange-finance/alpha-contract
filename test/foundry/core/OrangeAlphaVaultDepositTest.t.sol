// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeAlphaTestBase.sol";
import "./IOrangeAlphaVaultEvent.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract OrangeAlphaVaultDepositTest is OrangeAlphaTestBase, IOrangeAlphaVaultEvent {
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

    /* ========== EXTERNAL FUNCTIONS ========== */

    function test_deposit_Revert1() public {
        vm.expectRevert(bytes(ErrorsAlpha.INVALID_AMOUNT));
        vault.deposit(0, address(this), 9_900 * 1e6);
        vm.expectRevert(bytes(ErrorsAlpha.INVALID_AMOUNT));
        vault.deposit(1000, address(this), 0);
    }

    function test_deposit_Revert2() public {
        vm.expectRevert(bytes(ErrorsAlpha.INVALID_DEPOSIT_AMOUNT));
        vault.deposit(1, address(this), 1);
    }

    function test_deposit_Revert3LessMaxAssets() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        vm.expectRevert(bytes(ErrorsAlpha.LESS_MAX_ASSETS));
        vault.deposit(10_000 * 1e6, address(this), 5_000 * 1e6);
    }

    function test_deposit_Success0() public {
        //initial depositing
        uint256 _initialBalance = token1.balanceOf(address(this));
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        //assertion
        assertEq(vault.balanceOf(address(this)), 10_000 * 1e6 - 1e4);
        uint256 _realAssets = _initialBalance - token1.balanceOf(address(this));
        assertEq(_realAssets, 10_000 * 1e6);
        assertEq(token1.balanceOf(address(vault)), 10_000 * 1e6);
    }

    function test_deposit_Success1() public {
        // second depositing without liquidity (_additionalLiquidity = 0)
        // underhedge
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        //assertion
        assertEq(vault.balanceOf(address(this)), 19_900 * 1e6 - 1e4);
        assertEq(token1.balanceOf(address(vault)), 19_900 * 1e6);
    }

    function test_deposit_Success2Overhedge() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        // consoleUnderlyingAssets();

        //get current position and balance for assertion
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        uint _debtBalance0 = debtToken0.balanceOf(address(vault));
        uint _aBalance1 = aToken1.balanceOf(address(vault));
        uint _beforeBalance1 = token1.balanceOf(address(this));
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
        IOrangeAlphaVault.Positions memory _position = vault.computeTargetPositionByShares(
            _debtBalance0,
            _aBalance1,
            0,
            _beforeBalance1,
            _shares,
            vault.totalSupply()
        );
        (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
        uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
        (, currentTick, , , , , ) = pool.slot0();
        (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentTick.getSqrtRatioAtTick(),
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _targetLiquidity
        );

        //deposit
        vault.deposit(_shares, address(this), 10_000 * 1e6);

        //assertion
        //Vault token balance
        assertEq(vault.balanceOf(address(this)), 10_000 * 1e6 + _shares - 1e4);
        //Position
        assertApproxEqRel(debtToken0.balanceOf(address(vault)), _debtBalance0 + _position.debtAmount0, 1e16);
        assertApproxEqRel(aToken1.balanceOf(address(vault)), _aBalance1 + _position.collateralAmount1, 1e16);
        IOrangeAlphaVault.UnderlyingAssets memory __underlyingAssets = vault.getUnderlyingBalances();
        assertApproxEqRel(
            __underlyingAssets.liquidityAmount0,
            _underlyingAssets.liquidityAmount0 + _targetAmount0,
            1e16
        );
        assertApproxEqRel(
            __underlyingAssets.liquidityAmount1,
            _underlyingAssets.liquidityAmount1 + _targetAmount1,
            1e16
        );
        //Balance
        assertEq(token0.balanceOf(address(this)), 10_000 ether); // no change
        assertGt(token1.balanceOf(address(this)), _beforeBalance1 - (10_000 * 1e6));
        assertApproxEqRel(token1.balanceOf(address(this)), _beforeBalance1 - (10_000 * 1e6), 1e16);
    }

    function test_deposit_Success3Underhedge() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 50e6, 0);
        // consoleUnderlyingAssets();

        //get current position and balance for assertion
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        uint _debtBalance0 = debtToken0.balanceOf(address(vault));
        uint _aBalance1 = aToken1.balanceOf(address(vault));
        uint _beforeBalance1 = token1.balanceOf(address(this));
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
        IOrangeAlphaVault.Positions memory _position = vault.computeTargetPositionByShares(
            _debtBalance0,
            _aBalance1,
            0,
            _beforeBalance1,
            _shares,
            vault.totalSupply()
        );
        (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
        uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
        (, currentTick, , , , , ) = pool.slot0();
        (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentTick.getSqrtRatioAtTick(),
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _targetLiquidity
        );

        //deposit
        vault.deposit(_shares, address(this), 10_000 * 1e6);

        //assertion
        //Vault token balance
        assertEq(vault.balanceOf(address(this)), 10_000 * 1e6 + _shares - 1e4);
        //Position
        assertApproxEqRel(debtToken0.balanceOf(address(vault)), _debtBalance0 + _position.debtAmount0, 1e16);
        assertApproxEqRel(aToken1.balanceOf(address(vault)), _aBalance1 + _position.collateralAmount1, 1e16);
        IOrangeAlphaVault.UnderlyingAssets memory __underlyingAssets = vault.getUnderlyingBalances();
        assertApproxEqRel(
            __underlyingAssets.liquidityAmount0,
            _underlyingAssets.liquidityAmount0 + _targetAmount0,
            1e16
        );
        assertApproxEqRel(
            __underlyingAssets.liquidityAmount1,
            _underlyingAssets.liquidityAmount1 + _targetAmount1,
            1e16
        );
        //Balance
        assertEq(token0.balanceOf(address(this)), 10_000 ether); // no change
        assertGt(token1.balanceOf(address(this)), _beforeBalance1 - (10_000 * 1e6));
        assertApproxEqRel(token1.balanceOf(address(this)), _beforeBalance1 - (10_000 * 1e6), 1e16);
    }

    function test_deposit_Success4Quater() public {
        //overhedge
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        // consoleUnderlyingAssets();

        //get current position and balance for assertion
        IOrangeAlphaVault.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        uint _debtBalance0 = debtToken0.balanceOf(address(vault));
        uint _aBalance1 = aToken1.balanceOf(address(vault));
        uint _beforeBalance1 = token1.balanceOf(address(this));
        uint256 _shares = (vault.convertToShares(2500 * 1e6) * 9900) / MAGIC_SCALE_1E4;
        IOrangeAlphaVault.Positions memory _position = vault.computeTargetPositionByShares(
            _debtBalance0,
            _aBalance1,
            0,
            _beforeBalance1,
            _shares,
            vault.totalSupply()
        );
        (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
        uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
        (, currentTick, , , , , ) = pool.slot0();
        (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentTick.getSqrtRatioAtTick(),
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _targetLiquidity
        );

        //deposit
        vault.deposit(_shares, address(this), 2500 * 1e6);

        //assertion
        //Vault token balance
        assertEq(vault.balanceOf(address(this)), 10_000 * 1e6 + _shares - 1e4);
        //Position
        assertApproxEqRel(debtToken0.balanceOf(address(vault)), _debtBalance0 + _position.debtAmount0, 1e16);
        assertApproxEqRel(aToken1.balanceOf(address(vault)), _aBalance1 + _position.collateralAmount1, 1e16);
        IOrangeAlphaVault.UnderlyingAssets memory __underlyingAssets = vault.getUnderlyingBalances();
        assertApproxEqRel(
            __underlyingAssets.liquidityAmount0,
            _underlyingAssets.liquidityAmount0 + _targetAmount0,
            1e16
        );
        assertApproxEqRel(
            __underlyingAssets.liquidityAmount1,
            _underlyingAssets.liquidityAmount1 + _targetAmount1,
            1e16
        );
        //Balance
        assertEq(token0.balanceOf(address(this)), 10_000 ether); // no change
        assertGt(token1.balanceOf(address(this)), _beforeBalance1 - (2500 * 1e6));
        assertApproxEqRel(token1.balanceOf(address(this)), _beforeBalance1 - (2500 * 1e6), 1e16);
    }

    function test_deposit_Success5RefundZeroOverhedge() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        uint _Beforebal = token1.balanceOf(address(this));
        // console2.log(_vaultBalBefore, "vaultBalBefore");
        //deposit
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        assertEq(token1.balanceOf(address(this)), _Beforebal - 10_000 * 1e6);
    }

    function test_deposit_Success6RefundZeroUnderhedge() public {
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 50e6, 0);
        uint _Beforebal = token1.balanceOf(address(this));
        // console2.log(_vaultBalBefore, "vaultBalBefore");
        //deposit
        vault.deposit(9999528849, address(this), 9999999995);
        assertEq(token1.balanceOf(address(this)), _Beforebal - 9999999995);
    }
}
