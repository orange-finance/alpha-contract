// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import {UniswapV3LiquidityPoolManager, IUniswapV3LiquidityPoolManager} from "../../../contracts/liquidityPoolManager/UniswapV3LiquidityPoolManager.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {TickMath} from "../../../contracts/libs/uniswap/TickMath.sol";
import {OracleLibrary} from "../../../contracts/libs/uniswap/OracleLibrary.sol";
import {FullMath, LiquidityAmounts} from "../../../contracts/libs/uniswap/LiquidityAmounts.sol";

contract UniswapV3LiquidityPoolManagerTest is BaseTest {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr public uniswapAddr;

    UniswapV3LiquidityPoolManager public liquidityPool;
    IUniswapV3Pool public pool;
    ISwapRouter public router;
    IERC20 public token0;
    IERC20 public token1;
    IERC721 public nft;

    int24 public lowerTick = -205680;
    int24 public upperTick = -203760;
    int24 public currentTick;

    // currentTick = -204714;

    function setUp() public virtual {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr500);
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);
        router = ISwapRouter(uniswapAddr.routerAddr);

        liquidityPool = new UniswapV3LiquidityPoolManager();
        //initialize
        address[] memory _references = new address[](4);
        _references[0] = address(this);
        _references[1] = address(pool);
        _references[2] = address(token0);
        _references[3] = address(token1);
        liquidityPool.initialize(new uint256[](0), _references);

        //set Ticks for testing
        (, int24 _tick, , , , , ) = pool.slot0();
        currentTick = _tick;

        //deal
        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        deal(tokenAddr.wethAddr, carol, 10_000 ether);
        deal(tokenAddr.usdcAddr, carol, 10_000_000 * 1e6);

        //approve
        token0.approve(address(liquidityPool), type(uint256).max);
        token1.approve(address(liquidityPool), type(uint256).max);
        vm.startPrank(carol);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function test_all_Success() public {
        // _consoleBalance();

        //compute liquidity
        uint128 _liquidity = liquidityPool.getLiquidityForAmounts(lowerTick, upperTick, 1 ether, 1000 * 1e6);

        //mint
        IUniswapV3LiquidityPoolManager.MintParams memory _mintParams = IUniswapV3LiquidityPoolManager.MintParams(
            lowerTick,
            upperTick,
            _liquidity
        );
        (uint _amount0, uint _amount1) = liquidityPool.mint(_mintParams);
        console2.log(_amount0, _amount1);

        //assertion of mint
        (uint _amount0_, uint _amount1_) = liquidityPool.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, _amount0_ + 1);
        assertEq(_amount1, _amount1_ + 1);

        uint128 _liquidity2 = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        console2.log(_liquidity2, "liquidity2");
        assertEq(_liquidity, _liquidity2);
        // _consoleBalance();

        //swap
        multiSwapByCarol();

        //compute current fee and position
        (uint256 fee0, uint256 fee1) = liquidityPool.getFeesEarned(lowerTick, upperTick);
        console2.log(fee0, fee1);
        (_amount0, _amount1) = liquidityPool.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        uint _balance0 = token0.balanceOf(address(this));
        uint _balance1 = token1.balanceOf(address(this));

        // burn and collect
        IUniswapV3LiquidityPoolManager.BurnParams memory _paramsBurn = IUniswapV3LiquidityPoolManager.BurnParams(
            lowerTick,
            upperTick,
            _liquidity
        );
        (uint burn0_, uint burn1_) = liquidityPool.burn(_paramsBurn);
        assertEq(_amount0, burn0_);
        assertEq(_amount1, burn1_);
        // _consoleBalance();

        IUniswapV3LiquidityPoolManager.CollectParams memory _collectParams = IUniswapV3LiquidityPoolManager
            .CollectParams(lowerTick, upperTick);
        (uint collect0, uint collect1) = liquidityPool.collect(_collectParams);
        console2.log(collect0, collect1);
        assertEq(_balance0 + fee0 + burn0_, token0.balanceOf(address(this)));
        assertEq(_balance1 + fee1 + burn1_, token1.balanceOf(address(this)));
        // _consoleBalance();
    }

    function test_allReverse_Success() public {
        //re-deploy contract
        liquidityPool = new UniswapV3LiquidityPoolManager();
        address[] memory _references = new address[](4);
        _references[0] = address(this);
        _references[1] = address(pool);
        _references[2] = address(token1);
        _references[3] = address(token0);
        liquidityPool.initialize(new uint256[](0), _references);
        token0.approve(address(liquidityPool), type(uint256).max);
        token1.approve(address(liquidityPool), type(uint256).max);

        // _consoleBalance();

        //compute liquidity
        uint128 _liquidity = liquidityPool.getLiquidityForAmounts(lowerTick, upperTick, 1000 * 1e6, 1 ether);

        //mint
        IUniswapV3LiquidityPoolManager.MintParams memory _mintParams = IUniswapV3LiquidityPoolManager.MintParams(
            lowerTick,
            upperTick,
            _liquidity
        );
        (uint _amount0, uint _amount1) = liquidityPool.mint(_mintParams);
        console2.log(_amount0, _amount1);

        //assertion of mint
        (uint _amount0_, uint _amount1_) = liquidityPool.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, _amount0_ + 1);
        assertEq(_amount1, _amount1_ + 1);

        uint128 _liquidity2 = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        console2.log(_liquidity2, "liquidity2");
        assertEq(_liquidity, _liquidity2);
        // _consoleBalance();

        //swap
        multiSwapByCarol();

        //compute current fee and position
        (uint256 fee0, uint256 fee1) = liquidityPool.getFeesEarned(lowerTick, upperTick);
        console2.log(fee0, fee1);
        (_amount0, _amount1) = liquidityPool.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        uint _balance0 = token1.balanceOf(address(this));
        uint _balance1 = token0.balanceOf(address(this));

        // burn and collect
        IUniswapV3LiquidityPoolManager.BurnParams memory _paramsBurn = IUniswapV3LiquidityPoolManager.BurnParams(
            lowerTick,
            upperTick,
            _liquidity
        );
        (uint burn0_, uint burn1_) = liquidityPool.burn(_paramsBurn);
        assertEq(_amount0, burn0_);
        assertEq(_amount1, burn1_);
        // _consoleBalance();

        IUniswapV3LiquidityPoolManager.CollectParams memory _collectParams = IUniswapV3LiquidityPoolManager
            .CollectParams(lowerTick, upperTick);
        (uint collect0, uint collect1) = liquidityPool.collect(_collectParams);
        console2.log(collect0, collect1);
        assertEq(_balance0 + fee0 + burn0_, token1.balanceOf(address(this)));
        assertEq(_balance1 + fee1 + burn1_, token0.balanceOf(address(this)));
        // _consoleBalance();
    }

    /* ========== TEST functions ========== */
    function swapByCarol(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        ISwapRouter.ExactInputSingleParams memory inputParams;
        if (_zeroForOne) {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: pool.fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        } else {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: pool.fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        }
        vm.prank(carol);
        amountOut_ = router.exactInputSingle(inputParams);
    }

    function multiSwapByCarol() internal {
        swapByCarol(true, 1 ether);
        swapByCarol(false, 2000 * 1e6);
        swapByCarol(true, 1 ether);
    }

    function _consoleBalance() internal view {
        console2.log("balances: ");
        console2.log(
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this)),
            token0.balanceOf(address(liquidityPool)),
            token1.balanceOf(address(liquidityPool))
        );
    }
}
