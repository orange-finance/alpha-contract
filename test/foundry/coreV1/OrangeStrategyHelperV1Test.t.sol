// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeVaultV1TestBase.sol";
import {OrangeStrategyHelperV1, ILiquidityPoolManager} from "../../../contracts/coreV1/OrangeStrategyHelperV1.sol";
import {UniswapV3Twap, IUniswapV3Pool} from "../../../contracts/libs/UniswapV3Twap.sol";

contract OrangeStrategyHelperV1Test is OrangeVaultV1TestBase {
    using UniswapV3Twap for IUniswapV3Pool;
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    OrangeStrategyHelperV1 public helper;

    function setUp() public override {
        super.setUp();
        helper = new OrangeStrategyHelperV1(address(vault));
        params.setHelper(address(helper));
    }

    function test_constructor_Success() public {
        assertEq(address(helper.vault()), address(vault));
        assertEq(helper.token0(), address(token0));
        assertEq(helper.token1(), address(token1));
        assertEq(helper.liquidityPool(), address(vault.liquidityPool()));
        assertEq(address(helper.params()), address(params));
        assertEq(helper.strategists(address(this)), true);
    }

    function test_onlyStrategist_Revert() public {
        vm.expectRevert(bytes("ONLY_STRATEGIST"));
        vm.prank(alice);
        helper.setStrategist(alice, false);
        vm.expectRevert(bytes("ONLY_STRATEGIST"));
        vm.prank(alice);
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 0, 0);
        vm.expectRevert(bytes("ONLY_STRATEGIST"));
        vm.prank(alice);
        helper.stoploss(currentTick);
    }

    function test_setStrategist_Success() public {
        helper.setStrategist(alice, true);
        assertEq(helper.strategists(alice), true);
    }

    function test_rebalance_Success() public {
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 0, 0);
        assertEq(helper.stoplossLowerTick(), stoplossLowerTick);
        assertEq(helper.stoplossUpperTick(), stoplossUpperTick);
    }

    function test_stoploss_Success() public {
        helper.stoploss(currentTick);
    }

    function test_checker_Success1() public {
        //position
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, -204620, -204600, 0, 0);

        (, int24 _currentTick, , , , , ) = pool.slot0();
        int24 _twap = pool.getTwap();
        console2.log("currentTick", _currentTick.toString());
        console2.log("twap", _twap.toString());

        (bool canExec, ) = helper.checker();
        assertEq(canExec, true);
    }

    function test_checker_Success2False() public {
        //no position
        (bool canExec, bytes memory execPayload) = helper.checker();
        assertEq(canExec, false);

        //position
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        helper.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, 0, 0);

        (, int24 _currentTick, , , , , ) = pool.slot0();
        int24 _twap = pool.getTwap();
        console2.log("currentTick", _currentTick.toString());
        console2.log("twap", _twap.toString());
        //currentTick -204714
        //twap -204714

        //both in range
        helper.rebalance(lowerTick, upperTick, -206280, -203160, 0, 0);
        (canExec, execPayload) = helper.checker();
        assertEq(canExec, false);

        swapByCarol(false, 1_000_000 * 1e6);
        console2.log("currentTick", ILiquidityPoolManager(vault.liquidityPool()).getCurrentTick().toString());

        //current is in and twap is out
        helper.rebalance(lowerTick, upperTick, -204510, -204500, 0, 0);
        (canExec, execPayload) = helper.checker();
        assertEq(canExec, false);

        // current is out and twap is in
        helper.rebalance(lowerTick, upperTick, -204730, -204710, 0, 0);
        (canExec, execPayload) = helper.checker();
        assertEq(canExec, false);
    }

    function test_getRebalancedLiquidity_Success() public {
        uint256 _hedgeRatio = 100e6;
        vault.deposit(10 ether, 10 ether, new bytes32[](0));
        uint128 _liquidity = helper.getRebalancedLiquidity(
            lowerTick,
            upperTick,
            stoplossLowerTick,
            stoplossUpperTick,
            _hedgeRatio
        );

        IOrangeVaultV1.Positions memory _position = helper.computeRebalancePosition(
            10 ether,
            lowerTick,
            upperTick,
            helper.getLtvByRange(stoplossUpperTick),
            _hedgeRatio
        );
        //compute liquidity
        (, int24 _currentTick, , , , , ) = pool.slot0();
        uint128 _liquidity2 = liquidityPool.getLiquidityForAmounts(
            lowerTick,
            upperTick,
            _position.token0Balance,
            _position.token1Balance
        );
        assertEq(_liquidity, _liquidity2);
    }

    function test_computeHedge_SuccessCase1() public {
        //price 2,944
        int24 _tick = -196445;
        // console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(10 ether, -197040, -195850, 72913000, 127200000);
    }

    function test_computeHedge_SuccessCase2() public {
        //price 2,911
        int24 _tick = -196558;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(10 ether, -197040, -195909, 72089000, 158760000);
    }

    function test_computeHedge_SuccessCase3() public {
        //price 1,886
        int24 _tick = -200900;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(10 ether, -200940, -199646, 62_764_000, 103_290_000);
    }

    function test_computeHedge_SuccessCase4() public {
        //price 2,619
        int24 _tick = -197613;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(10 ether, -198296, -197013, 72_948_000, 46_220_000);
    }

    function test_computeRebalancePosition_SuccessHedgeRatioZero() public {
        uint _ltv = 80e6;

        IOrangeVaultV1.Positions memory _position = helper.computeRebalancePosition(
            10 ether,
            lowerTick,
            upperTick,
            _ltv,
            0
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.collateralAmount0, "collateralAmount0");
        console.log(_position.debtAmount1, "debtAmount1");
        console.log(_position.token0Balance, "token0Balance");
        console.log(_position.token1Balance, "token1Balance");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");

        //assertion
        assertEq(_position.collateralAmount0, 0);
        assertEq(_position.debtAmount1, 0);
        //total amount
        uint _added0 = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(_position.token1Balance),
            address(token1),
            address(token0)
        );
        uint _total = _position.token0Balance + _added0;
        assertApproxEqRel(_total, 10 ether, 1e16);
    }

    function test_computeRebalancePosition_SuccessHedgeRatio() public {
        uint _ltv = 80e6;
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick, _ltv, 100e6);
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick, _ltv, 200e6);
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick, _ltv, 50e6);
    }

    function test_computeRebalancePosition_SuccessRange() public {
        uint256 _hedgeRatio = 100e6;
        uint _ltv = 80e6;
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick, _ltv, _hedgeRatio);
        _testComputeRebalancePosition(10 ether, lowerTick - 600, upperTick, _ltv, _hedgeRatio);
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick + 600, _ltv, _hedgeRatio);
    }

    function test_computeRebalancePosition_SuccessLtv() public {
        uint256 _hedgeRatio = 100e6;
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick, 80e6, _hedgeRatio);
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick, 60e6, _hedgeRatio);
        _testComputeRebalancePosition(10 ether, lowerTick, upperTick, 40e6, _hedgeRatio);
    }

    function test_getLtvByRange_Success1() public {
        uint _currentPrice = OracleLibrary.getQuoteAtTick(currentTick, 1 ether, address(token0), address(token1));
        uint256 _upperPrice = OracleLibrary.getQuoteAtTick(
            stoplossUpperTick,
            1 ether,
            address(token0),
            address(token1)
        );
        uint256 ltv_ = uint256(80000000).mulDiv(_currentPrice, _upperPrice);
        assertEq(ltv_, helper.getLtvByRange(stoplossUpperTick));
    }

    function _testComputeRebalancePosition(
        uint256 _assets0,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal {
        IOrangeVaultV1.Positions memory _position = helper.computeRebalancePosition(
            _assets0,
            _lowerTick,
            _upperTick,
            _ltv,
            _hedgeRatio
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.collateralAmount0, "collateralAmount0");
        console.log(_position.debtAmount1, "debtAmount1");
        console.log(_position.token0Balance, "token0Balance");
        console.log(_position.token1Balance, "token1Balance");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        //assertion
        //total amount
        uint _total = _position.collateralAmount0 + _position.token0Balance;
        if (_position.debtAmount1 > _position.token1Balance) {
            uint _debtToken0 = OracleLibrary.getQuoteAtTick(
                currentTick,
                uint128(_position.debtAmount1 - _position.token1Balance),
                address(token1),
                address(token0)
            );
            _total -= _debtToken0;
        } else {
            uint _addedToken0 = OracleLibrary.getQuoteAtTick(
                currentTick,
                uint128(_position.token1Balance - _position.debtAmount1),
                address(token1),
                address(token0)
            );
            _total += _addedToken0;
        }
        assertApproxEqRel(_total, _assets0, 1e16);
        //ltv
        uint256 _debt0 = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(_position.debtAmount1),
            address(token1),
            address(token0)
        );
        uint256 _computedLtv = (_debt0 * MAGIC_SCALE_1E8) / _position.collateralAmount0;
        assertApproxEqRel(_computedLtv, _ltv, 1e16);
        //hedge ratio
        uint256 _computedHedgeRatio = (_position.debtAmount1 * MAGIC_SCALE_1E8) / _position.token1Balance;
        // console2.log(_computedHedgeRatio, "computedHedgeRatio");
        assertApproxEqRel(_computedHedgeRatio, _hedgeRatio, 1e16);
    }
}
