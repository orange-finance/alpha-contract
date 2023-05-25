// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeVaultV1TestBase.sol";
import {OrangeStrategyImplV1, ErrorsV1, IOrangeVaultV1, OrangeStorageV1, IOrangeParametersV1, OrangeERC20} from "../../../contracts/coreV1/OrangeStrategyImplV1.sol";
import {Proxy} from "../../../contracts/libs/Proxy.sol";

contract OrangeStrategyImplV1Test is OrangeVaultV1TestBase {
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

    uint256 constant HEDGE_RATIO = 100e6; //100%
    ProxyMock proxy;

    function setUp() public override {
        super.setUp();
        proxy = new ProxyMock(address(params));
    }

    //access controls
    function test_rebalance_Revert1() public {
        vm.expectRevert(bytes(ErrorsV1.ONLY_HELPER));
        vm.prank(alice);
        proxy.rebalance(lowerTick, upperTick, IOrangeVaultV1.Positions(0, 0, 0, 0), 0);
        vm.expectRevert(bytes(ErrorsV1.ONLY_HELPER));
        vm.prank(alice);
        proxy.stoploss(0);
    }

    function test_checkTickSlippage_Success1() public {
        vm.expectRevert(bytes(ErrorsV1.HIGH_SLIPPAGE));
        helper.stoploss(0);
        vm.expectRevert(bytes(ErrorsV1.HIGH_SLIPPAGE));
        helper.stoploss(-204800);
    }

    function test_stoploss_Success1() public {
        helper.stoploss(currentTick);
        assertEq(vault.hasPosition(), false);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        assertEq(_liquidity, 0);
        assertEq(lendingPool.balanceOfDebt(), 0);
        assertEq(lendingPool.balanceOfCollateral(), 0);
        assertEq(token0.balanceOf(address(vault)), 0);
        assertEq(token1.balanceOf(address(vault)), 0);
    }

    function test_stoploss_Success2WithoutPosition() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(1);
        (, int24 _tick, , , , , ) = pool.slot0();
        helper.stoploss(_tick);
        //assertion
        assertEq(vault.hasPosition(), false);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        assertEq(_liquidity, 0);
        assertEq(lendingPool.balanceOfDebt(), 0);
        assertEq(lendingPool.balanceOfCollateral(), 0);
        assertApproxEqRel(token0.balanceOf(address(vault)), 10 ether, 1e16);
        assertEq(token1.balanceOf(address(vault)), 0);
    }

    function test_stoploss_Success3() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(1);
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);
        skip(1);

        (, int24 _tick, , , , , ) = pool.slot0();
        helper.stoploss(_tick);
        skip(1);
        (, _tick, , , , , ) = pool.slot0();
        helper.stoploss(_tick);
        //assertion
        assertEq(vault.hasPosition(), false);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        assertEq(_liquidity, 0);
        assertEq(lendingPool.balanceOfDebt(), 0);
        assertEq(lendingPool.balanceOfCollateral(), 0);
        assertApproxEqRel(token0.balanceOf(address(vault)), 10 ether, 1e16);
        assertEq(token1.balanceOf(address(vault)), 0);
    }

    function test_rebalance_RevertOnlyStrategists() public {
        IOrangeVaultV1.Positions memory _currentPosition = IOrangeVaultV1.Positions(0, 0, 0, 0);
        vm.expectRevert(bytes(ErrorsV1.ONLY_HELPER));
        vm.startPrank(alice);
        proxy.rebalance(0, 0, _currentPosition, 0);
    }

    function test_rebalance_RevertTickSpacing() public {
        uint256 _hedgeRatio = 100e6;
        vm.expectRevert(bytes("INVALID_TICKS"));
        helper.rebalance(-1, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);
    }

    function test_rebalance_RevertNewLiquidity() public {
        uint256 _hedgeRatio = 100e6;
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        uint128 _liquidity = helper.getRebalancedLiquidity(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        );

        vm.expectRevert(bytes(ErrorsV1.LESS_LIQUIDITY));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, _liquidity);
    }

    function test_rebalance_Success0() public {
        uint256 _hedgeRatio = 100e6;
        //totalSupply is zero
        int24 _newLowerTick = -207540;
        int24 _newUpperTick = -205680;
        int24 _newStoplossLowerTick = -208740;
        int24 _newStoplossUpperTick = -204480;
        helper.rebalance(_newLowerTick, _newUpperTick, _newStoplossLowerTick, _newStoplossUpperTick, _hedgeRatio, 0);
        assertEq(vault.lowerTick(), _newLowerTick);
        assertEq(vault.upperTick(), _newUpperTick);
        assertEq(vault.hasPosition(), true);
    }

    function test_rebalance_SuccessHedgeRatioZero() public {
        uint _ltv = 80e6;
        uint256 _hedgeRatio = 0;
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        skip(1);

        int24 _newLowerTick = -207540;
        int24 _newUpperTick = -205680;
        uint128 _liquidity = helper.getRebalancedLiquidity(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        );
        helper.rebalance(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio,
            (_liquidity * 9900) / MAGIC_SCALE_1E4
        );

        uint128 _newLiquidity = liquidityPool.getCurrentLiquidity(_newLowerTick, _newUpperTick);
        assertApproxEqRel(_liquidity, _newLiquidity, 1e16);
    }

    function test_rebalance_Success1() public {
        uint256 _hedgeRatio = 100e6;
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        skip(1);

        //rebalance
        uint128 _liquidity = (helper.getRebalancedLiquidity(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        ) * 9900) / MAGIC_SCALE_1E4;
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, _liquidity);

        // uint128 _newLiquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        // assertApproxEqRel(_liquidity, _newLiquidity, 1e16);

        assertEq(vault.hasPosition(), true);
        assertEq(vault.lowerTick(), lowerTick);
        assertEq(vault.upperTick(), upperTick);
    }

    function test_rebalance_Success2UnderRange() public {
        uint256 _hedgeRatio = 100e6;
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        skip(1);
        swapByCarol(true, 1000 ether); //current price under lowerPrice
        skip(1 days);

        //rebalance
        int24 _newLowerTick = -207540;
        int24 _newUpperTick = -205680;
        uint128 _minLiquidity = (helper.getRebalancedLiquidity(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        ) * 9990) / MAGIC_SCALE_1E4;
        _rebalance(_newLowerTick, _newUpperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, _minLiquidity);

        uint128 _newLiquidity = liquidityPool.getCurrentLiquidity(_newLowerTick, _newUpperTick);
        assertApproxEqRel(_minLiquidity, _newLiquidity, 1e16);
    }

    function test_rebalance_Success3OverRange() public {
        uint256 _hedgeRatio = 100e6;
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        skip(1);
        swapByCarol(false, 1_000_000 * 1e6); //current price over upperPrice
        skip(1 days);

        //rebalance
        int24 _newLowerTick = -204600;
        int24 _newUpperTick = -202500;
        uint128 _minLiquidity = (helper.getRebalancedLiquidity(
            _newLowerTick,
            _newUpperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        ) * 9990) / MAGIC_SCALE_1E4;
        _rebalance(_newLowerTick, _newUpperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, _minLiquidity);

        uint128 _newLiquidity = liquidityPool.getCurrentLiquidity(_newLowerTick, _newUpperTick);
        assertApproxEqRel(_minLiquidity, _newLiquidity, 1e16);
    }

    //Supply and Borrow
    function test_rebalance_SuccessCase1() public {
        //deposit
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        (, currentTick, , , , , ) = pool.slot0();
        uint256 _hedgeRatio = 100e6;
        _consolecomputeRebalancePosition(
            10 ether,
            currentTick,
            lowerTick,
            upperTick,
            helper.getLtvByRange(stoplossUpperTick),
            _hedgeRatio
        );

        skip(1);
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);
    }

    //Repay and Withdraw
    function test_rebalance_SuccessCase2() public {
        uint256 _hedgeRatio = 100e6;
        //deposit
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        skip(1);
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);

        _hedgeRatio = 50e6;
        // (, currentTick, , , , , ) = pool.slot0();
        // _consolecomputeRebalancePosition(
        //     10 ether,
        //     currentTick,
        //     lowerTick,
        //     upperTick,
        //     helper.getLtvByRange(stoplossUpperTick),
        //     _hedgeRatio
        // );
        // return;

        skip(1);
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);
    }

    //Repay and Supply
    function test_rebalance_SuccessCase3() public {
        uint256 _hedgeRatio = 100e6;
        //deposit
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        skip(1);
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);

        _hedgeRatio = 100e6;
        // upperTick = -204000;
        // stoplossUpperTick = -203400;
        stoplossUpperTick = -201060;

        // (, currentTick, , , , , ) = pool.slot0();
        // _consolecomputeRebalancePosition(
        //     10 ether,
        //     currentTick,
        //     lowerTick,
        //     upperTick,
        //     helper.getLtvByRange(stoplossUpperTick),
        //     _hedgeRatio
        // );
        // return;

        skip(1);
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);
    }

    //Borrow and Withdraw
    function test_rebalance_SuccessCase4() public {
        uint256 _hedgeRatio = 100e6;
        //deposit
        vault.deposit(10 ether, 10 ether, new bytes32[](0));

        stoplossUpperTick = -200160;
        skip(1);
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);

        _hedgeRatio = 95e6;
        upperTick = -204000;
        stoplossUpperTick = -203880;
        // (, currentTick, , , , , ) = pool.slot0();
        // _consolecomputeRebalancePosition(
        //     10 ether,
        //     currentTick,
        //     lowerTick,
        //     upperTick,
        //     helper.getLtvByRange(stoplossUpperTick),
        //     _hedgeRatio
        // );
        // return;

        skip(1);
        _rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, 1);
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
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, _hedgeRatio, _minNewLiquidity);

        // consoleUnderlyingAssets();
        consoleCurrentPosition();

        (, currentTick, , , , , ) = pool.slot0(); //retrieve current tick

        //assertions
        //ltv
        uint256 _ltv = helper.getLtvByRange(stoplossUpperTick);
        uint256 _collateral = lendingPool.balanceOfCollateral();
        uint256 _debt = lendingPool.balanceOfDebt();
        uint256 _debtAligned = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(_debt),
            address(token1),
            address(token0)
        );
        uint256 _computedLtv = (_debtAligned * MAGIC_SCALE_1E8) / _collateral;
        // console.log("computedLtv", _computedLtv);
        // console.log("ltv", _ltv);
        assertApproxEqRel(_computedLtv, _ltv, 1e16);

        //hedge ratio
        IOrangeVaultV1.UnderlyingAssets memory _underlyingAssets = vault.getUnderlyingBalances();
        uint256 _hedgeRatioComputed = (_debt * MAGIC_SCALE_1E8) / _underlyingAssets.liquidityAmount1;
        // console.log("hedgeRatioComputed", _hedgeRatioComputed);
        assertApproxEqRel(_hedgeRatioComputed, _hedgeRatio, 1e16);

        //total balance
        //after assets
        uint _afterAssets = vault.totalAssets();
        // console.log("beforeAssets", _beforeAssets);
        // console.log("afterAssets", _afterAssets);
        assertApproxEqRel(_afterAssets, _beforeAssets, 1e16);
    }

    function test_addLiquidityInRebalance_Success0() public {
        //no need to swap
        token0.transfer(address(vault), 10 ether);
        token1.transfer(address(vault), 10000 * 1e6);
        vault.addLiquidityInRebalance(lowerTick, upperTick, 10 ether, 10000 * 1e6);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        assertGt(_liquidity, 0);
    }

    function test_addLiquidityInRebalance_Success1() public {
        //swap 0 to 1
        token0.transfer(address(vault), 10 ether);
        token1.transfer(address(vault), 5000 * 1e6);
        vault.addLiquidityInRebalance(lowerTick, upperTick, 5 ether, 10000 * 1e6);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        assertGt(_liquidity, 0);
    }

    function test_addLiquidityInRebalance_Success2() public {
        //swap 1 to 0
        token0.transfer(address(vault), 3 ether);
        token1.transfer(address(vault), 20000 * 1e6);
        vault.addLiquidityInRebalance(lowerTick, upperTick, 5 ether, 10000 * 1e6);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        assertGt(_liquidity, 0);
    }

    function _consolecomputeRebalancePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) private view {
        IOrangeVaultV1.Positions memory _position = helper.computeRebalancePosition(
            _assets,
            _lowerTick,
            _upperTick,
            _ltv,
            _hedgeRatio
        );
        console.log("++++++++ _consolecomputeRebalancePosition ++++++++");
        console.log(_position.collateralAmount0, "collateralAmount0");
        console.log(_position.debtAmount1, "debtAmount1");
        console.log(_position.token0Balance, "token0Balance");
        console.log(_position.token1Balance, "token1Balance");
    }
}

contract ProxyMock is Proxy, OrangeStorageV1 {
    constructor(address _params) OrangeERC20("OrangeStrategyImplV1", "OrangeStrategyImplV1") {
        params = IOrangeParametersV1(_params);
    }

    function rebalance(int24, int24, IOrangeVaultV1.Positions memory, uint128) external {
        _delegate(params.strategyImpl());
    }

    function stoploss(int24) external {
        _delegate(params.strategyImpl());
    }

    function addLiquidityInRebalance(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _targetAmount0,
        uint256 _targetAmount1
    ) external {
        _delegate(params.strategyImpl());
    }
}
