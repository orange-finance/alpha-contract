// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeVaultV1TestBase.sol";
import {OrangeStrategyImplV1, ErrorsV1, IOrangeVaultV1, OrangeStorageV1, IOrangeParametersV1, OrangeERC20} from "../../../contracts/coreV1/OrangeStrategyImplV1.sol";
import {Proxy} from "../../../contracts/libs/Proxy.sol";
import {IERC20Decimals} from "../../../contracts/coreV1/OrangeERC20.sol";

contract OrangeVaultV1Test is OrangeVaultV1TestBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    uint256 constant HEDGE_RATIO = 100e6; //100%
    OrangeStrategyHelperV1 public helper;

    function setUp() public override {
        super.setUp();
        helper = new OrangeStrategyHelperV1(address(vault));
        params.setHelper(address(helper));
    }

    /* ========== CONSTRUCTOR ========== */
    function test_constructor_Success() public {
        assertEq(address(vault.token0()), address(token0));
        assertEq(address(vault.token1()), address(token1));
        assertEq(vault.decimals(), IERC20Decimals(address(token0)).decimals());

        assertEq(address(vault.liquidityPool()), address(liquidityPool));
        assertEq(token0.allowance(address(vault), address(liquidityPool)), type(uint256).max);
        assertEq(token1.allowance(address(vault), address(liquidityPool)), type(uint256).max);

        assertEq(address(vault.lendingPool()), address(lendingPool));
        assertEq(token0.allowance(address(vault), address(lendingPool)), type(uint256).max);
        assertEq(token1.allowance(address(vault), address(lendingPool)), type(uint256).max);

        assertEq(address(vault.params()), address(params));
        assertEq(address(vault.router()), address(router));
        assertEq(vault.routerFee(), 500);
        assertEq(address(vault.balancer()), address(balancer));
    }

    /* ========== ACCESS CONTROLS ========== */
    function test_rebalance_Revert1() public {
        vm.expectRevert(bytes(ErrorsV1.ONLY_HELPER));
        vm.prank(alice);
        vault.rebalance(lowerTick, upperTick, IOrangeVaultV1.Positions(0, 0, 0, 0), 0);
        vm.expectRevert(bytes(ErrorsV1.ONLY_HELPER));
        vm.prank(alice);
        vault.stoploss(0);
    }

    /* ========== VIEW FUNCTIONS ========== */
    function test_convertToShares_Success0() public {
        assertEq(vault.convertToShares(0), 0); //zero
    }

    function test_convertToShares_Success1() public {
        //assert shares after deposit
        uint256 _shares = vault.convertToShares(10_000 * 1e6);
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        assertEq(_shares, vault.convertToShares(10_000 * 1e6));
    }

    function test_convertToShares_Success2() public {
        uint256 _shares = vault.convertToShares(10_000 * 1e6);
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        assertApproxEqRel(10_000 * 1e6, _shares, 1e16);
    }

    function test_convertToAssets_Success0() public {
        assertEq(vault.convertToAssets(0), 0);
    }

    function test_convertToAssets_Success1() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        uint256 _shares = 2500 * 1e6;
        assertEq(vault.convertToAssets(_shares), _shares.mulDiv(vault.totalAssets(), vault.totalSupply()));
    }

    function test_convertToAssets_Success2() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        assertApproxEqRel(vault.convertToAssets(10_000 * 1e6), 10_000 * 1e6, 1e16);
    }

    function test_totalAssets_Success0() public {
        assertEq(vault.totalAssets(), 0);
    }

    function test_totalAssets_Success1() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        assertEq(vault.totalAssets(), 10 ether);
    }

    function test_totalAssets_Success2() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        assertApproxEqRel(vault.totalAssets(), 10 ether, 1e16);
    }

    function test_alignTotalAsset_Success0() public {
        //liquidityAmount0 == amount0Debt
        uint256 totalAlignedAssets = vault.alignTotalAsset(10 ether, 10000 * 1e6, 10 ether, 10000 * 1e6);
        // console2.log(totalAlignedAssets, "totalAlignedAssets");
        assertEq(totalAlignedAssets, 20 ether);
    }

    function test_alignTotalAsset_Success1() public {
        //liquidityAmount0 < amount0Debt
        uint256 totalAlignedAssets = vault.alignTotalAsset(10 ether, 10000 * 1e6, 11 ether, 14000 * 1e6);
        // console2.log(totalAlignedAssets, "totalAlignedAssets");

        uint256 amount1deducted = (14000 - 10000) * 1e6;
        amount1deducted = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(amount1deducted),
            address(token1),
            address(token0)
        );
        assertEq(totalAlignedAssets, 21 ether - amount1deducted);
    }

    function test_alignTotalAsset_Success2() public {
        //liquidityAmount0 > amount0Debt
        uint256 totalAlignedAssets = vault.alignTotalAsset(12 ether, 14000 * 1e6, 10 ether, 10000 * 1e6);
        // console2.log(totalAlignedAssets, "totalAlignedAssets");

        uint256 amount1Added = (14000 - 10000) * 1e6;
        amount1Added = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(amount1Added),
            address(token1),
            address(token0)
        );
        assertEq(totalAlignedAssets, 22 ether + amount1Added);
    }

    function test_getUnderlyingBalances_Success0() public {
        //zero
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        assertEq(_underlyingAssets.liquidityAmount0, 0);
        assertEq(_underlyingAssets.liquidityAmount1, 0);
        assertEq(_underlyingAssets.accruedFees0, 0);
        assertEq(_underlyingAssets.accruedFees1, 0);
        assertEq(_underlyingAssets.vaultAmount0, 0);
        assertEq(_underlyingAssets.vaultAmount1, 0);
    }

    function test_getUnderlyingBalances_Success1() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        //zero
        assertGt(_underlyingAssets.liquidityAmount0, 0);
        assertGt(_underlyingAssets.liquidityAmount1, 0);
        //Greater than or equial 0
        assertGe(_underlyingAssets.vaultAmount0, 0);
        assertGe(_underlyingAssets.vaultAmount1, 0);
    }

    function test_getUnderlyingBalances_Success2() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

        multiSwapByCarol(); //swapped
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        //Greater than 0
        assertGt(_underlyingAssets.liquidityAmount0, 0);
        assertGt(_underlyingAssets.liquidityAmount1, 0);
        //Greater than 0
        assertGt(_underlyingAssets.accruedFees0, 0);
        assertGt(_underlyingAssets.accruedFees1, 0);
        //Greater than or equial 0
        assertGe(_underlyingAssets.vaultAmount0, 0);
        assertGe(_underlyingAssets.vaultAmount1, 0);
    }

    function test_computeTargetPositionByShares_Success() public {
        IOrangeVaultV1.Positions memory _position = vault.computeTargetPositionByShares(
            100 ether,
            200 * 1e6,
            300 ether,
            400 * 1e6,
            25,
            100
        );
        assertEq(_position.collateralAmount0, 100 ether / 4);
        assertEq(_position.debtAmount1, (200 * 1e6) / 4);
        assertEq(_position.token0Balance, 300 ether / 4);
        assertEq(_position.token1Balance, (400 * 1e6) / 4);
    }

    /* ========== DEPOSIT ========== */

    function test_deposit_Revert1() public {
        vm.expectRevert(bytes(ErrorsV1.INVALID_AMOUNT));
        vault.deposit(0, 9_900 * 1e6, new bytes32[](0));
        vm.expectRevert(bytes(ErrorsV1.INVALID_AMOUNT));
        vault.deposit(1000, 0, new bytes32[](0));
    }

    function test_deposit_Revert2() public {
        vm.expectRevert(bytes(ErrorsV1.INVALID_DEPOSIT_AMOUNT));
        vault.deposit(1, 1, new bytes32[](0));
    }

    function test_deposit_Revert3LessMaxAssets() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        vm.expectRevert(bytes(ErrorsV1.LESS_MAX_ASSETS));
        vault.deposit(10 ether, 5_000 * 1e6, new bytes32[](0));
    }

    function test_deposit_Success0() public {
        //initial depositing
        uint256 _initialBalance = token0.balanceOf(address(this));
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        //assertion
        assertEq(vault.balanceOf(address(this)), 10 ether - (1 ether / 1000));
        uint256 _realAssets = _initialBalance - token0.balanceOf(address(this));
        assertEq(_realAssets, 10 ether);
        assertEq(token0.balanceOf(address(vault)), 10 ether);
    }

    function test_deposit_Success1() public {
        // second depositing without liquidity (_additionalLiquidity = 0)
        // underhedge
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        uint256 _shares = (vault.convertToShares(10 ether) * 9900) / MAGIC_SCALE_1E4;
        vault.deposit(_shares, 10 ether, new bytes32[](0));
        //assertion
        assertEq(vault.balanceOf(address(this)), 10 ether + _shares - (1 ether / 1000));
        assertEq(token0.balanceOf(address(vault)), 10 ether + _shares);
    }

    function test_deposit_Success2Overhedge() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        // consoleUnderlyingAssets();

        //get current position and balance for assertion
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        uint _aBalance0 = lendingPool.balanceOfCollateral();
        uint _debtBalance1 = lendingPool.balanceOfDebt();
        uint _beforeBalance0 = token0.balanceOf(address(this));
        uint256 _shares = (vault.convertToShares(10 ether) * 9900) / MAGIC_SCALE_1E4;
        IOrangeVaultV1.Positions memory _position = vault.computeTargetPositionByShares(
            _aBalance0,
            _debtBalance1,
            _beforeBalance0,
            0,
            _shares,
            vault.totalSupply()
        );
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
        (, currentTick, , , , , ) = pool.slot0();
        (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentTick.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            _targetLiquidity
        );

        //deposit
        vault.deposit(_shares, 10 ether, new bytes32[](0));

        //assertion
        //Vault token balance
        assertEq(vault.balanceOf(address(this)), 10 ether + _shares - (1 ether / 1000));
        // //Position
        assertApproxEqRel(lendingPool.balanceOfDebt(), _debtBalance1 + _position.debtAmount1, 1e16);
        assertApproxEqRel(lendingPool.balanceOfCollateral(), _aBalance0 + _position.collateralAmount0, 1e16);
        IOrangeVaultV1.UnderlyingAssets memory __underlyingAssets = vault.getUnderlyingBalances();
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
        assertGt(token0.balanceOf(address(this)), _beforeBalance0 - (10 ether));
        assertApproxEqRel(token0.balanceOf(address(this)), _beforeBalance0 - (10 ether), 1e16);
    }

    function test_deposit_Success3Underhedge() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 50e6, 0);
        // consoleUnderlyingAssets();

        //get current position and balance for assertion
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        uint _debtBalance1 = lendingPool.balanceOfDebt();
        uint _aBalance0 = lendingPool.balanceOfCollateral();
        uint _beforeBalance0 = token0.balanceOf(address(this));
        uint256 _shares = (vault.convertToShares(10 ether) * 9900) / MAGIC_SCALE_1E4;
        IOrangeVaultV1.Positions memory _position = vault.computeTargetPositionByShares(
            _aBalance0,
            _debtBalance1,
            _beforeBalance0,
            0,
            _shares,
            vault.totalSupply()
        );
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
        (, currentTick, , , , , ) = pool.slot0();
        (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentTick.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            _targetLiquidity
        );

        //deposit
        vault.deposit(_shares, 10 ether, new bytes32[](0));

        //assertion
        //Vault token balance
        assertEq(vault.balanceOf(address(this)), 10 ether + _shares - (1 ether / 1000));
        //Position
        assertApproxEqRel(lendingPool.balanceOfDebt(), _debtBalance1 + _position.debtAmount1, 1e16);
        assertApproxEqRel(lendingPool.balanceOfCollateral(), _aBalance0 + _position.collateralAmount0, 1e16);
        IOrangeVaultV1.UnderlyingAssets memory __underlyingAssets = vault.getUnderlyingBalances();
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
        assertGt(token0.balanceOf(address(this)), _beforeBalance0 - (10 ether));
        assertApproxEqRel(token0.balanceOf(address(this)), _beforeBalance0 - (10 ether), 1e16);
    }

    function test_deposit_Success4Quater() public {
        //overhedge
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        // consoleUnderlyingAssets();

        //get current position and balance for assertion
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        uint _debtBalance1 = lendingPool.balanceOfDebt();
        uint _aBalance0 = lendingPool.balanceOfCollateral();
        uint _beforeBalance0 = token0.balanceOf(address(this));
        uint256 _shares = (vault.convertToShares(2 ether) * 9900) / MAGIC_SCALE_1E4;
        IOrangeVaultV1.Positions memory _position = vault.computeTargetPositionByShares(
            _aBalance0,
            _debtBalance1,
            _beforeBalance0,
            0,
            _shares,
            vault.totalSupply()
        );
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        uint128 _targetLiquidity = uint128(uint256(_liquidity).mulDiv(_shares, vault.totalSupply()));
        (, currentTick, , , , , ) = pool.slot0();
        (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            currentTick.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            _targetLiquidity
        );

        //deposit
        vault.deposit(_shares, 2 ether, new bytes32[](0));

        //assertion
        //Vault token balance
        assertEq(vault.balanceOf(address(this)), 10 ether + _shares - (1 ether / 1000));
        //Position
        assertApproxEqRel(lendingPool.balanceOfDebt(), _debtBalance1 + _position.debtAmount1, 1e16);
        assertApproxEqRel(lendingPool.balanceOfCollateral(), _aBalance0 + _position.collateralAmount0, 1e16);
        IOrangeVaultV1.UnderlyingAssets memory __underlyingAssets = vault.getUnderlyingBalances();
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
        assertGt(token0.balanceOf(address(this)), _beforeBalance0 - (2 ether));
        assertApproxEqRel(token0.balanceOf(address(this)), _beforeBalance0 - (2 ether), 1e16);
    }

    function test_deposit_Success5RefundZeroOverhedge() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        uint _Beforebal = token0.balanceOf(address(this));
        // console2.log(_vaultBalBefore, "vaultBalBefore");
        //deposit
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        assertEq(token0.balanceOf(address(this)), _Beforebal - 10 ether);
    }

    function test_deposit_Success6RefundZeroUnderhedge() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 80e6, 0);
        uint _Beforebal = token0.balanceOf(address(this));
        // console2.log(_vaultBalBefore, "vaultBalBefore");
        //deposit
        vault.deposit(9 ether, 9000014870508283742, new bytes32[](0));
        assertEq(token0.balanceOf(address(this)), _Beforebal - 9000014870508283742);
    }

    /* ========== REDEEM ========== */
    function test_redeem_Revert1() public {
        vm.expectRevert(bytes(ErrorsV1.INVALID_AMOUNT));
        vault.redeem(0, 9_900 * 1e6);
    }

    function test_redeem_Revert2() public {
        uint256 _shares = vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(1);
        vm.expectRevert(bytes(ErrorsV1.LESS_AMOUNT));
        vault.redeem(_shares, 1000 ether * 1e6);
    }

    function test_redeem_Success0NoPosition() public {
        uint _beforeBalance0 = token0.balanceOf(address(this));
        uint256 _shares = vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(8 days);

        uint256 _assets = (vault.convertToAssets(_shares) * 9900) / MAGIC_SCALE_1E4;
        uint256 _realAssets = vault.redeem(_shares, _assets);

        //assertion
        assertEq(10 ether - (1 ether / 1000), _realAssets);
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(token0.balanceOf(address(this)), _beforeBalance0 - 10 ether + _realAssets);
    }

    function test_redeem_Success1Max() public {
        uint _beforeBalance0 = token0.balanceOf(address(this));
        uint256 _shares = vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(8 days);
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        uint256 _assets = (vault.convertToAssets(_shares) * 9900) / MAGIC_SCALE_1E4;
        uint256 _realAssets = vault.redeem(_shares, _assets);
        //assertion
        assertApproxEqRel(_realAssets, _assets - (1 ether / 1000), 1e17);
        assertEq(vault.balanceOf(address(this)), 0);
        assertApproxEqRel(token0.balanceOf(address(this)), _beforeBalance0 - 10 ether + _realAssets, 1e16);
    }

    function test_redeem_Success2Quater() public {
        uint _beforeBalance0 = token0.balanceOf(address(this));
        uint256 _shares = vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(8 days);
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        // prepare for assetion
        uint128 _liquidity0 = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        uint256 _debtToken1 = lendingPool.balanceOfDebt();
        uint256 _aToken0 = lendingPool.balanceOfCollateral();

        //execute
        uint256 _assets = (vault.convertToAssets(_shares) * 9900) / MAGIC_SCALE_1E4;
        vault.redeem((_shares * 3) / 4, (_assets * 3) / 4);
        // assertion
        assertApproxEqRel(vault.balanceOf(address(this)), _shares / 4, 1e16);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        assertApproxEqRel(_liquidity, _liquidity0 / 4, 1e16);
        assertApproxEqRel(lendingPool.balanceOfDebt(), _debtToken1 / 4, 1e16);
        assertApproxEqRel(lendingPool.balanceOfCollateral(), _aToken0 / 4, 1e16);
        assertApproxEqRel(token0.balanceOf(address(this)), _beforeBalance0 - ((10 ether * 3) / 4), 1e16);
    }

    function test_redeem_Success3SurplusUSDCToETH() public {
        uint _beforeBalance0 = token0.balanceOf(address(this));
        uint256 _shares = vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(8 days);
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 50e6, 0);
        skip(1);

        uint256 _assets = (vault.convertToAssets(_shares) * 9900) / MAGIC_SCALE_1E4;
        uint256 _realAssets = vault.redeem(_shares, _assets);
        // //assertion
        assertApproxEqRel(_realAssets, _assets, 1e16);
        assertEq(vault.balanceOf(address(this)), 0);
        assertApproxEqRel(token0.balanceOf(address(this)), _beforeBalance0, 1e16);
    }
}
