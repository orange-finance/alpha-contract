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
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        vault.deposit(0, address(this), 9_900 * 1e6);
        vm.expectRevert(bytes(Errors.INVALID_AMOUNT));
        vault.deposit(1000, address(this), 0);
    }

    function test_deposit_Revert2() public {
        vm.expectRevert(bytes(Errors.INVALID_DEPOSIT_AMOUNT));
        vault.deposit(1, address(this), 1);
    }

    function test_deposit_Success0() public {
        //initial depositing
        uint256 _initialBalance = token1.balanceOf(address(this));
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        //assertion
        assertEq(vault.balanceOf(address(this)), 10_000 * 1e6);
        uint256 _realAssets = _initialBalance - token1.balanceOf(address(this));
        assertEq(_realAssets, 10_000 * 1e6);
        assertEq(token1.balanceOf(address(vault)), 10_000 * 1e6);
    }

    function test_deposit_Success1() public {
        // second depositing without liquidity
        vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
        uint256 _shares = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
        vault.deposit(_shares, address(this), 10_000 * 1e6);
        //assertion
        assertEq(vault.balanceOf(address(this)), 19_900 * 1e6);
        assertEq(token1.balanceOf(address(vault)), 19_900 * 1e6);
    }

    function test_deposit_Success2() public {
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
        assertEq(vault.balanceOf(address(this)), 10_000 * 1e6 + _shares);
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
        assertGt(token0.balanceOf(address(this)), 0);
        assertGt(token1.balanceOf(address(this)), _beforeBalance1 - (10_000 * 1e6));
        assertApproxEqRel(token1.balanceOf(address(this)), _beforeBalance1 - (10_000 * 1e6), 1e16);
    }

    // // function test_depositLiquidityByShares_Success0Max() public {
    // //     uint _shares = 10_000 * 1e6;
    // //     vault.deposit(_shares, address(this), 10_000 * 1e6);
    // //     vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
    // //     skip(1);

    // //     (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
    // //     uint128 _additionalLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
    // //     (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
    // //     (uint256 _additionalLiquidityAmount0, uint256 _additionalLiquidityAmount1) = LiquidityAmounts
    // //         .getAmountsForLiquidity(
    // //             _sqrtRatioX96,
    // //             _ticks.lowerTick.getSqrtRatioAtTick(),
    // //             _ticks.upperTick.getSqrtRatioAtTick(),
    // //             _additionalLiquidity
    // //         );
    // //     IOrangeAlphaVault.Balances memory _balance = IOrangeAlphaVault.Balances(
    // //         _additionalLiquidityAmount0 + 1,
    // //         _additionalLiquidityAmount1 + 1
    // //     );
    // //     token0.transfer(address(vault), _balance.balance0);
    // //     token1.transfer(address(vault), _balance.balance1);
    // //     vault.depositLiquidityByShares(_balance, _shares, vault.totalSupply(), _ticks);
    // //     assertEq(_balance.balance0 - _additionalLiquidityAmount0, 1);
    // //     assertEq(_balance.balance1 - _additionalLiquidityAmount1, 1);
    // // }

    // // function test_depositLiquidityByShares_Success1Quater() public {
    // //     uint _shares = 10_000 * 1e6;
    // //     vault.deposit(_shares, address(this), 10_000 * 1e6);
    // //     vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
    // //     skip(1);

    // //     (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
    // //     uint128 _additionalLiquidity = uint128(uint256(_liquidity).mulDiv(_shares / 4, vault.totalSupply()));
    // //     (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
    // //     (uint256 _additionalLiquidityAmount0, uint256 _additionalLiquidityAmount1) = LiquidityAmounts
    // //         .getAmountsForLiquidity(
    // //             _sqrtRatioX96,
    // //             _ticks.lowerTick.getSqrtRatioAtTick(),
    // //             _ticks.upperTick.getSqrtRatioAtTick(),
    // //             _additionalLiquidity
    // //         );
    // //     IOrangeAlphaVault.Balances memory _balance = IOrangeAlphaVault.Balances(
    // //         _additionalLiquidityAmount0 + 1,
    // //         _additionalLiquidityAmount1 + 1
    // //     );
    // //     token0.transfer(address(vault), _balance.balance0);
    // //     token1.transfer(address(vault), _balance.balance1);
    // //     vault.depositLiquidityByShares(_balance, _shares / 4, vault.totalSupply(), _ticks);
    // //     assertEq(_balance.balance0 - _additionalLiquidityAmount0, 1);
    // //     assertEq(_balance.balance1 - _additionalLiquidityAmount1, 1);
    // // }

    // function test_swapSurplusAmountInDeposit_Success2Flashborrow0() public {
    //     vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
    //     vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

    //     //get current position and balance for assertion
    //     uint256 _shares = vault.convertToShares(10_000 * 1e6);
    //     (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
    //     uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
    //     (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
    //     (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
    //         _sqrtRatioX96,
    //         _ticks.lowerTick.getSqrtRatioAtTick(),
    //         _ticks.upperTick.getSqrtRatioAtTick(),
    //         _targetLiquidity
    //     );
    //     IOrangeAlphaVault.Balances memory _balance = IOrangeAlphaVault.Balances(
    //         _targetAmount0 - 10,
    //         _targetAmount1 + 10
    //     );
    //     uint256 _beforeBalance0 = token0.balanceOf(address(vault));
    //     uint256 _beforeBalance1 = token1.balanceOf(address(vault));

    //     //transfer token0 and token1 to vault
    //     token0.transfer(address(vault), _balance.balance0);
    //     token1.transfer(address(vault), _balance.balance1);
    //     vault.depositLiquidityByShares(_balance, _shares, vault.totalSupply(), _ticks);
    //     //assertion
    //     assertEq(token0.balanceOf(address(vault)), _beforeBalance0);
    //     assertApproxEqRel(_beforeBalance1, token1.balanceOf(address(vault)), 1e18);
    // }

    // function test_swapSurplusAmountInDeposit_Success3Flashborrow1() public {
    //     vault.deposit(10_000 * 1e6, address(this), 10_000 * 1e6);
    //     vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

    //     //get current position and balance for assertion
    //     uint256 _shares = vault.convertToShares(10_000 * 1e6);
    //     (uint128 _liquidity, , , , ) = pool.positions(vault.getPositionID());
    //     uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
    //     (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
    //     (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
    //         _sqrtRatioX96,
    //         _ticks.lowerTick.getSqrtRatioAtTick(),
    //         _ticks.upperTick.getSqrtRatioAtTick(),
    //         _targetLiquidity
    //     );
    //     IOrangeAlphaVault.Balances memory _balance = IOrangeAlphaVault.Balances(
    //         _targetAmount0 + 1e14,
    //         _targetAmount1 - 10
    //     );
    //     uint256 _beforeBalance0 = token0.balanceOf(address(vault));
    //     uint256 _beforeBalance1 = token1.balanceOf(address(vault));

    //     //transfer token0 and token1 to vault
    //     token0.transfer(address(vault), _balance.balance0);
    //     token1.transfer(address(vault), _balance.balance1);
    //     vault.depositLiquidityByShares(_balance, _shares, vault.totalSupply(), _ticks);
    //     //assertion
    //     assertApproxEqRel(token0.balanceOf(address(vault)), _beforeBalance0 - 1e14, 1e18);
    //     assertEq(token1.balanceOf(address(vault)), 0);
    // }
}
