// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeAlphaBase.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IAaveV3Pool} from "../../../contracts/interfaces/IAaveV3Pool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Errors} from "../../../contracts/libs/Errors.sol";
import {TickMath} from "../../../contracts/vendor/uniswap/TickMath.sol";
import {OracleLibrary} from "../../../contracts/vendor/uniswap/OracleLibrary.sol";
import {FullMath, LiquidityAmounts} from "../../../contracts/vendor/uniswap/LiquidityAmounts.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract OrangeAlphaComputePositionTest is OrangeAlphaBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    function test_computeHedge_SuccessCase1() public {
        //price 2,944
        int24 _tick = -196445;
        // console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputePosition(
            100_216 * 1e6,
            _tick,
            -197040,
            -195850,
            72913000,
            127200000
        );
    }

    function test_computeHedge_SuccessCase2() public {
        //price 2,911
        int24 _tick = -196558;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputePosition(
            100_304 * 1e6,
            _tick,
            -197040,
            -195909,
            72089000,
            158760000
        );
    }

    function test_computeHedge_SuccessCase3() public {
        //price 1,886
        int24 _tick = -200900;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputePosition(
            97_251 * 1e6,
            _tick,
            -200940,
            -199646,
            62_764_000,
            103_290_000
        );
    }

    function test_computeHedge_SuccessCase4() public {
        //price 2,619
        int24 _tick = -197613;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        _testComputePosition(
            96_719 * 1e6,
            _tick,
            -198296,
            -197013,
            72_948_000,
            46_220_000
        );
    }

    function test_computePosition_SuccessHedgeRatio() public {
        uint _ltv = 80e6;
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            _ltv,
            100e6
        );
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            _ltv,
            200e6
        );
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            _ltv,
            50e6
        );
    }

    function test_computePosition_SuccessRange() public {
        uint256 _hedgeRatio = 100e6;
        uint _ltv = 80e6;
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            _ltv,
            _hedgeRatio
        );
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick - 600,
            upperTick,
            _ltv,
            _hedgeRatio
        );
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick + 600,
            _ltv,
            _hedgeRatio
        );
    }

    function test_computePosition_SuccessLtv() public {
        uint256 _hedgeRatio = 100e6;
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            80e6,
            _hedgeRatio
        );
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            60e6,
            _hedgeRatio
        );
        _testComputePosition(
            10_000 * 1e6,
            currentTick,
            lowerTick,
            upperTick,
            40e6,
            _hedgeRatio
        );
    }

    function _testComputePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal {
        IOrangeAlphaVault.Position memory _position = vault.computePosition(
            _assets,
            _currentTick,
            _lowerTick,
            _upperTick,
            _ltv,
            _hedgeRatio
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.supplyAmount1, "supplyAmount1");
        console.log(_position.addedAmount0, "addedAmount0");
        console.log(_position.addedAmount1, "addedAmount1");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        //assertion
        //total amount
        uint _total = _position.supplyAmount1 + _position.addedAmount1;
        if (_position.debtAmount0 > _position.addedAmount0) {
            uint _debtUsdc = OracleLibrary.getQuoteAtTick(
                _currentTick,
                uint128(_position.debtAmount0 - _position.addedAmount0),
                address(token0),
                address(token1)
            );
            _total -= _debtUsdc;
        } else {
            uint _addedUsdc = OracleLibrary.getQuoteAtTick(
                _currentTick,
                uint128(_position.addedAmount0 - _position.debtAmount0),
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
        uint256 _computedLtv = (_debtUsdc * MAGIC_SCALE_1E8) /
            _position.supplyAmount1;
        assertApproxEqRel(_computedLtv, _ltv, 1e16);
        //hedge ratio
        uint256 _computedHedgeRatio = (_position.debtAmount0 *
            MAGIC_SCALE_1E8) / _position.addedAmount0;
        // console2.log(_computedHedgeRatio, "computedHedgeRatio");
        assertApproxEqRel(_computedHedgeRatio, _hedgeRatio, 1e16);
    }

    function _quoteEthPriceByTick(int24 _tick) internal view returns (uint256) {
        return
            OracleLibrary.getQuoteAtTick(
                _tick,
                1 ether,
                address(token0),
                address(token1)
            );
    }
}
