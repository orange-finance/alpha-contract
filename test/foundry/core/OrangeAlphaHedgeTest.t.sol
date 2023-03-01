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

contract OrangeAlphaHedgeTest is BaseTest {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    uint256 MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.AaveAddr aaveAddr;
    AddressHelper.UniswapAddr uniswapAddr;
    ISwapRouter router;

    IUniswapV3Pool pool;
    IAaveV3Pool aave;
    IERC20 weth;
    IERC20 usdc;
    IERC20 debtToken0; //weth
    IERC20 aToken1; //usdc

    int24 lowerTick = -205680;
    int24 upperTick = -203760;
    int24 stoplossLowerTick = -206280;
    int24 stoplossUpperTick = -203160;
    int24 currentTick;
    // currentTick = -204714;

    //parameters
    uint256 constant DEPOSIT_CAP = 1_000_000 * 1e6;
    uint256 constant TOTAL_DEPOSIT_CAP = 1_000_000 * 1e6;
    uint32 constant MAX_LTV = 80000000;

    function setUp() public {
        (tokenAddr, aaveAddr, uniswapAddr) = AddressHelper.addresses(
            block.chainid
        );

        router = ISwapRouter(uniswapAddr.routerAddr); //for test
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);
        aave = IAaveV3Pool(aaveAddr.poolAddr);
        debtToken0 = IERC20(aaveAddr.vDebtWethAddr);
        aToken1 = IERC20(aaveAddr.ausdcAddr);

        //set Ticks for testing
        (, int24 _tick, , , , , ) = pool.slot0();
        currentTick = _tick;
        console2.log(currentTick.toString(), "currentTick");

        //deal
        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        deal(tokenAddr.usdcAddr, alice, 10_000_000 * 1e6);
        deal(tokenAddr.wethAddr, carol, 10_000 ether);
        deal(tokenAddr.usdcAddr, carol, 10_000_000 * 1e6);

        //approve
        weth.approve(address(aave), type(uint256).max);
        usdc.approve(address(aave), type(uint256).max);
        vm.startPrank(carol);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function test_computeHedgeBalance() public {
        uint256 _depositAmount = 10_000 * 1e6;
        (uint256 _supply, uint256 _borrow) = _computeSupplyAndBorrow(
            _depositAmount
        );
        aave.supply(address(usdc), _supply, address(this), 0);
        aave.borrow(address(weth), _borrow, 2, 0, address(this));
        uint256 remainingAmount = _depositAmount - _supply;
        //compute liquidity
        uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
            currentTick.getSqrtRatioAtTick(),
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            _borrow,
            remainingAmount
        );
        console2.log(_liquidity, "_liquidity");
    }

    function _computeSupplyAndBorrow(uint256 _assets)
        internal
        view
        returns (uint256 supply_, uint256 borrow_)
    {
        uint256 _ltv = _getLtvByRange(currentTick, lowerTick, upperTick);
        // uint256 _hedgeRate = MAGIC_SCALE_1E8; //100%

        // ETH/USDC
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                currentTick.getSqrtRatioAtTick(),
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                1e18 //ここはてきとう
            );
        console2.log(_amount0, "_amount0");
        console2.log(_amount1, "_amount1");
        uint256 _amount0Dollar = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(_amount0),
            address(weth),
            address(usdc)
        );

        supply_ =
            (_assets * MAGIC_SCALE_1E8) /
            (MAGIC_SCALE_1E8 + _ltv.mulDiv(_amount1, _amount0Dollar));

        uint256 _borrowUsdc = supply_.mulDiv(_ltv, MAGIC_SCALE_1E8);
        //borrowing usdc amount to weth
        borrow_ = OracleLibrary.getQuoteAtTick(
            currentTick,
            uint128(_borrowUsdc),
            address(usdc),
            address(weth)
        );
        console2.log(supply_, "supply_");
        console2.log(borrow_, "borrow_");
    }

    function _getLtvByRange(
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (uint256 ltv_) {
        uint256 _currentPrice = _quoteEthPriceByTick(_currentTick);
        uint256 _lowerPrice = _quoteEthPriceByTick(_lowerTick);
        uint256 _upperPrice = _quoteEthPriceByTick(_upperTick);

        ltv_ = MAX_LTV;
        if (_currentPrice > _upperPrice) {
            // ltv_ = maxLtv;
        } else if (_currentPrice < _lowerPrice) {
            ltv_ = ltv_.mulDiv(_lowerPrice, _upperPrice);
        } else {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
        }
    }

    function _quoteEthPriceByTick(int24 _tick) internal view returns (uint256) {
        return
            OracleLibrary.getQuoteAtTick(
                _tick,
                1 ether,
                address(weth),
                address(usdc)
            );
    }
}
