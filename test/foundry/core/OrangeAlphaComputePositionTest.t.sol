// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

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

contract OrangeAlphaComputePositionTest is BaseTest {
    struct Position {
        uint256 debtAmount0;
        uint256 supplyAmount1;
        uint256 addedAmount0;
        uint256 addedAmount1;
    }

    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;

    uint256 MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    IUniswapV3Pool pool;
    IERC20 token0;
    IERC20 token1;

    int24 lowerTick = -205680;
    int24 upperTick = -203760;
    int24 stoplossLowerTick = -206280;
    int24 stoplossUpperTick = -203160;
    int24 currentTick;

    // currentTick = -204714;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);

        //set Ticks for testing
        (, int24 _tick, , , , , ) = pool.slot0();
        currentTick = _tick;
        console2.log(currentTick.toString(), "currentTick");
    }

    function test_computeHedgeBalance1() public {
        //price 2,944
        int24 _tick = -196445;
        // console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        Position memory _position = _computePosition(
            100_216 * 1e6,
            _tick,
            -197040,
            -195850,
            72913000,
            127200000
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.supplyAmount1, "supplyAmount1");
        console.log(_position.addedAmount0, "addedAmount0");
        console.log(_position.addedAmount1, "addedAmount1");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
    }

    function test_computeHedgeBalance2() public {
        //price 2,911
        int24 _tick = -196558;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        Position memory _position = _computePosition(
            100_304 * 1e6,
            _tick,
            -197040,
            -195909,
            72089000,
            158760000
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.supplyAmount1, "supplyAmount1");
        console.log(_position.addedAmount0, "addedAmount0");
        console.log(_position.addedAmount1, "addedAmount1");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
    }

    function test_computeHedgeBalance3() public {
        //price 1,886
        int24 _tick = -200900;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        Position memory _position = _computePosition(
            97_251 * 1e6,
            _tick,
            -200940,
            -199646,
            62_764_000,
            103_290_000
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.supplyAmount1, "supplyAmount1");
        console.log(_position.addedAmount0, "addedAmount0");
        console.log(_position.addedAmount1, "addedAmount1");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
    }

    function test_computeHedgeBalance4() public {
        //price 2,619
        int24 _tick = -197613;
        console2.log(_quoteEthPriceByTick(_tick), "ethPrice");

        Position memory _position = _computePosition(
            96_719 * 1e6,
            _tick,
            -198296,
            -197013,
            72_948_000,
            46_220_000
        );
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
        console.log(_position.debtAmount0, "debtAmount0");
        console.log(_position.supplyAmount1, "supplyAmount1");
        console.log(_position.addedAmount0, "addedAmount0");
        console.log(_position.addedAmount1, "addedAmount1");
        console2.log("++++++++++++++++++++++++++++++++++++++++++++++++");
    }

    function _computePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal view returns (Position memory position_) {
        if (_assets == 0) return Position(0, 0, 0, 0);

        // compute ETH/USDC amount ration to add liquidity
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                _currentTick.getSqrtRatioAtTick(),
                _lowerTick.getSqrtRatioAtTick(),
                _upperTick.getSqrtRatioAtTick(),
                1e18 //any amount
            );
        console2.log(_amount0, "_amount0");
        console2.log(_amount1, "_amount1");
        uint256 _amount0Usdc = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_amount0),
            address(token0),
            address(token1)
        );
        console2.log(_amount0Usdc, "_amount0Usdc");

        //compute collateral/asset ratio
        uint256 _x = MAGIC_SCALE_1E8.mulDiv(_amount0Usdc, _amount1);
        console2.log(_x, "_x");
        uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
            _ltv +
            MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
            MAGIC_SCALE_1E8.mulDiv(
                _ltv,
                (_hedgeRatio.mulDiv(_x, MAGIC_SCALE_1E8))
            );
        console2.log(_collateralRatioReciprocal, "_collateralRatioReciprocal");

        //Collateral
        position_.supplyAmount1 = _assets.mulDiv(
            MAGIC_SCALE_1E8,
            _collateralRatioReciprocal
        );

        uint256 _borrowUsdc = position_.supplyAmount1.mulDiv(
            _ltv,
            MAGIC_SCALE_1E8
        );
        //borrowing usdc amount to weth
        position_.debtAmount0 = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_borrowUsdc),
            address(token1),
            address(token0)
        );

        // amount added on Uniswap
        position_.addedAmount0 = position_.debtAmount0.mulDiv(
            MAGIC_SCALE_1E8,
            _hedgeRatio
        );
        position_.addedAmount1 = position_.addedAmount0.mulDiv(
            _amount1,
            _amount0
        );
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
