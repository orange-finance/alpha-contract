// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@test/foundry/coreV1/OrangeVaultV1Initializable/Fixture.t.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TickMath} from "@src/libs/uniswap/TickMath.sol";
import {LiquidityAmounts, FullMath} from "@src/libs/uniswap/LiquidityAmounts.sol";
import {IERC20Decimals} from "@src/coreV1/proxy/OrangeERC20Initializable.sol";
import {ErrorsV1} from "@src/coreV1/ErrorsV1.sol";
import {IOrangeVaultV1Initializable} from "@src/interfaces/IOrangeVaultV1Initializable.sol";
import {ARB_FORK_BLOCK_DEFAULT} from "../../Config.sol";

contract OrangeVaultV1InitializableTest is Fixture {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    uint256 constant HEDGE_RATIO = 100e6; //100%

    function setUp() public override {
        vm.createSelectFork("arb", ARB_FORK_BLOCK_DEFAULT);
        super.setUp();
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

    function test_reInitialization_Revert() public {
        IOrangeVaultV1Initializable.VaultInitializeParams memory _params = IOrangeVaultV1Initializable
            .VaultInitializeParams(
                "Orange Vault",
                "ORANGE",
                address(token0),
                address(token1),
                address(1),
                address(2),
                address(3),
                address(router),
                500,
                address(balancer)
            );
        vm.expectRevert("Initializable: contract is already initialized");
        IOrangeVaultV1Initializable(vaultImpl).initialize(_params);
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
        //Greater than or equal 0
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
        //Greater than or equal 0
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

    function test_addDeposit_Revert4Cap() public {
        //deposit cap over
        vm.expectRevert(bytes(ErrorsV1.CAPOVER));
        vault.deposit(9_001 ether, 9_001 ether, new bytes32[](0));

        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        params.setDepositCap(10 ether);
        vm.expectRevert(bytes(ErrorsV1.CAPOVER));
        vault.deposit(20 ether, 21 ether, new bytes32[](0));
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

    function test_emitAction_Success() public {
        vm.expectEmit(true, true, true, true);
        emit Action(IOrangeVaultV1.ActionType.MANUAL, address(this), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        vault.emitAction(IOrangeVaultV1.ActionType.MANUAL);
    }

    function test_allowlisted_Success() public {
        /**
         * assume that the proofs are as follows:
         *
         *  root: 0xe47075d54b1d9bb2eca1aaf74c2a73615b83ee5e7b02a4323bb50db8c32cea00
         *
         *  address:  0x7e5f4552091a69125d5dfcb7b8c2659029395bdf // alice
         *  proof: [
         *  '0x94a6fc29a44456b36232638a7042431c9c91b910df1c52187179085fac1560e9',
         *  '0x7ffe805cbf69104033955da6db7de982b4b029fc5459b3133ba12ed30a67ad85'
         *  ]
         *
         *  address:  0x2b5ad5c4795c026514f8317c7a215e218dccd6cf // bob
         *  proof: [
         *  '0x3322f33946a3c503c916c8fc29768a547f01fa665e1eb22f9f66cf7e5a262012',
         *  '0x7ffe805cbf69104033955da6db7de982b4b029fc5459b3133ba12ed30a67ad85'
         *  ]
         *
         *  address:  0x6813eb9362372eef6200f3b1dbc3f819671cba69 // carol
         *  proof: [
         *  '0x1143df8268b94bd6292fdd7c9b8af39a79f764cfc03ae006844446bc91203927',
         *  '0x3dd73fb4bffdc562cf570f864739747e2ab5d46ab397c4466da14e0e06b57d56'
         *  ]
         *
         *  address:  0x1eff47bc3a10a45d4b230b5d10e37751fe6aa718 // david
         *  proof: [
         *  '0x1bec7c333d3d0c3eef8c6199a402856509c3f869d25408cc1cc2208d0371db0e',
         *  '0x3dd73fb4bffdc562cf570f864739747e2ab5d46ab397c4466da14e0e06b57d56'
         *  ]
         */

        vm.prank(carol);
        token0.approve(address(vault), type(uint256).max);

        params.setAllowlistEnabled(true);
        params.setMerkleRoot(0xe47075d54b1d9bb2eca1aaf74c2a73615b83ee5e7b02a4323bb50db8c32cea00);
        bytes32[] memory _p1 = new bytes32[](2);
        _p1[0] = 0x1143df8268b94bd6292fdd7c9b8af39a79f764cfc03ae006844446bc91203927;
        _p1[1] = 0x3dd73fb4bffdc562cf570f864739747e2ab5d46ab397c4466da14e0e06b57d56;

        vm.prank(carol);
        vault.deposit(10 ether, 10 ether, _p1);
        assertTrue(vault.balanceOf(carol) > 0);
    }

    function test_allowlisted_Revert() public {
        params.setAllowlistEnabled(true);
        params.setMerkleRoot(keccak256(abi.encodePacked(uint(1))));
        bytes32[] memory _merkleProof = new bytes32[](1);
        _merkleProof[0] = bytes32(0);
        vm.expectRevert(bytes(ErrorsV1.MERKLE_ALLOWLISTED));
        vault.deposit(10 ether, 10 ether, _merkleProof);
    }
}
