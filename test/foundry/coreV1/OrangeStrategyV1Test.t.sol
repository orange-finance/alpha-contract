// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeVaultV1TestBase.sol";
import {OrangeStrategyV1} from "../../../contracts/coreV1/OrangeStrategyV1.sol";

contract OrangeStrategyV1Test is OrangeVaultV1TestBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    OrangeStrategyV1 strategy;

    function setUp() public override {
        super.setUp();
        strategy = new OrangeStrategyV1(address(vault), address(params));
    }

    // function test_computeHedge_SuccessCase1() public {
    //     //price 2,944
    //     int24 _tick = -196445;
    //     // console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

    //     _testComputeRebalancePosition(10 ether, _tick, -197040, -195850, 72913000, 127200000);
    // }

    // function test_computeHedge_SuccessCase2() public {
    //     //price 2,911
    //     int24 _tick = -196558;
    //     console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

    //     _testComputeRebalancePosition(10 ether, _tick, -197040, -195909, 72089000, 158760000);
    // }

    // function test_computeHedge_SuccessCase3() public {
    //     //price 1,886
    //     int24 _tick = -200900;
    //     console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

    //     _testComputeRebalancePosition(10 ether, _tick, -200940, -199646, 62_764_000, 103_290_000);
    // }

    // function test_computeHedge_SuccessCase4() public {
    //     //price 2,619
    //     int24 _tick = -197613;
    //     console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

    //     _testComputeRebalancePosition(10 ether, _tick, -198296, -197013, 72_948_000, 46_220_000);
    // }

    // function test_computeRebalancePosition_SuccessHedgeRatioZero() public {
    //     uint _ltv = 80e6;

    //     IOrangeVaultV1.Positions memory _position = vault.computeRebalancePosition(
    //         10 ether,
    //         currentTick,
    //         lowerTick,
    //         upperTick,
    //         _ltv,
    //         0
    //     );
    //     console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
    //     console.log(_position.collateralAmount0, "collateralAmount0");
    //     console.log(_position.debtAmount1, "debtAmount1");
    //     console.log(_position.token0Balance, "token0Balance");
    //     console.log(_position.token1Balance, "token1Balance");
    //     console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");

    //     //assertion
    //     assertEq(_position.collateralAmount0, 0);
    //     assertEq(_position.debtAmount1, 0);
    //     //total amount
    //     uint _added0 = OracleLibrary.getQuoteAtTick(
    //         currentTick,
    //         uint128(_position.token0Balance),
    //         address(token1),
    //         address(token0)
    //     );
    //     uint _total = _position.token0Balance + _added0;
    //     assertApproxEqRel(_total, 10 ether, 1e16);
    // }

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

    function _testComputeRebalancePosition(
        uint256 _assets0,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal {
        IOrangeVaultV1.Positions memory _position = strategy.computeRebalancePosition(
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
