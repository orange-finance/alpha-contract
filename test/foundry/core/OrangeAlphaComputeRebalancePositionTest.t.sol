// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeAlphaTestBase.sol";

contract OrangeAlphaComputeRebalancePositionTest is OrangeAlphaTestBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    function test_computeHedge_SuccessCase1() public {
        //price 2,944
        int24 _tick = -196445;
        // console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(100_216 * 1e6, _tick, -197040, -195850, 72913000, 127200000);
    }

    function test_computeHedge_SuccessCase2() public {
        //price 2,911
        int24 _tick = -196558;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(100_304 * 1e6, _tick, -197040, -195909, 72089000, 158760000);
    }

    function test_computeHedge_SuccessCase3() public {
        //price 1,886
        int24 _tick = -200900;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(97_251 * 1e6, _tick, -200940, -199646, 62_764_000, 103_290_000);
    }

    function test_computeHedge_SuccessCase4() public {
        //price 2,619
        int24 _tick = -197613;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputeRebalancePosition(96_719 * 1e6, _tick, -198296, -197013, 72_948_000, 46_220_000);
    }

    function test_computeRebalancePosition_SuccessHedgeRatioZero() public {
        uint _ltv = 80e6;

        IOrangeAlphaVault.Positions memory _position = vault.computeRebalancePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            _ltv,
            0
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.collateralAmount1, "collateralAmount1");
        console.log(_position.token0Balance, "token0Balance");
        console.log(_position.token1Balance, "token1Balance");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");

        //assertion
        assertEq(_position.debtAmount0, 0);
        assertEq(_position.collateralAmount1, 0);
        //total amount
        uint _addedUsdc = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(_position.token0Balance),
            address(token0),
            address(token1)
        );
        uint _total = _position.token1Balance + _addedUsdc;
        assertApproxEqRel(_total, 10_000 * 1e6, 1e16);
    }

    function test_computeRebalancePosition_SuccessHedgeRatio() public {
        uint _ltv = 80e6;
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick, _ltv, 100e6);
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick, _ltv, 200e6);
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick, _ltv, 50e6);
    }

    function test_computeRebalancePosition_SuccessRange() public {
        uint256 _hedgeRatio = 100e6;
        uint _ltv = 80e6;
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick, _ltv, _hedgeRatio);
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick - 600, upperTick, _ltv, _hedgeRatio);
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick + 600, _ltv, _hedgeRatio);
    }

    function test_computeRebalancePosition_SuccessLtv() public {
        uint256 _hedgeRatio = 100e6;
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick, 80e6, _hedgeRatio);
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick, 60e6, _hedgeRatio);
        _testComputeRebalancePosition(10_000 * 1e6, currentTick, lowerTick, upperTick, 40e6, _hedgeRatio);
    }

    function _testComputeRebalancePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal {
        IOrangeAlphaVault.Positions memory _position = vault.computeRebalancePosition(
            _assets,
            _currentTick,
            _lowerTick,
            _upperTick,
            _ltv,
            _hedgeRatio
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.collateralAmount1, "collateralAmount1");
        console.log(_position.token0Balance, "token0Balance");
        console.log(_position.token1Balance, "token1Balance");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        //assertion
        //total amount
        uint _total = _position.collateralAmount1 + _position.token1Balance;
        if (_position.debtAmount0 > _position.token0Balance) {
            uint _debtUsdc = OracleLibrary.getQuoteAtTick(
                _currentTick,
                uint128(_position.debtAmount0 - _position.token0Balance),
                address(token0),
                address(token1)
            );
            _total -= _debtUsdc;
        } else {
            uint _addedUsdc = OracleLibrary.getQuoteAtTick(
                _currentTick,
                uint128(_position.token0Balance - _position.debtAmount0),
                address(token0),
                address(token1)
            );
            _total += _addedUsdc;
        }
        assertApproxEqRel(_total, _assets, 1e16);
        //ltv
        uint256 _debtUsdc = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_position.debtAmount0),
            address(token0),
            address(token1)
        );
        uint256 _computedLtv = (_debtUsdc * MAGIC_SCALE_1E8) / _position.collateralAmount1;
        assertApproxEqRel(_computedLtv, _ltv, 1e16);
        //hedge ratio
        uint256 _computedHedgeRatio = (_position.debtAmount0 * MAGIC_SCALE_1E8) / _position.token0Balance;
        // console2.log(_computedHedgeRatio, "computedHedgeRatio");
        assertApproxEqRel(_computedHedgeRatio, _hedgeRatio, 1e16);
    }
}
