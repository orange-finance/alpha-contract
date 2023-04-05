// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {OrangeAlphaResolver} from "../../../contracts/core/OrangeAlphaResolver.sol";
import {UniswapV3Twap} from "../../../contracts/libs/UniswapV3Twap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";
import {OrangeAlphaParameters} from "../../../contracts/core/OrangeAlphaParameters.sol";

contract OrangeAlphaResolverTest is BaseTest {
    using UniswapV3Twap for IUniswapV3Pool;
    using Ints for int24;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    OrangeAlphaResolver resolver;
    OrangeAlphaVaultMockForResolver vault;
    OrangeAlphaParameters params;
    IUniswapV3Pool pool;
    ISwapRouter public router;
    IERC20 token0;
    IERC20 token1;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);
        router = ISwapRouter(uniswapAddr.routerAddr); //for test

        //deploy parameters
        params = new OrangeAlphaParameters();

        //deploy vault
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);
        vault = new OrangeAlphaVaultMockForResolver(address(pool));

        //deploy resolver
        resolver = new OrangeAlphaResolver(address(vault), address(params));

        //deal
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        token1.approve(address(router), type(uint256).max);
    }

    /* ========== CONSTRUCTOR ========== */
    function test_constructor_Success() public {
        assertEq(address(resolver.vault()), address(vault));
        assertEq(address(resolver.params()), address(params));
    }

    function test_checker_Success1() public {
        (, int24 _currentTick, , , , , ) = pool.slot0();
        int24 _twap = pool.getTwap();
        console2.log("currentTick", _currentTick.toString());
        console2.log("twap", _twap.toString());

        vault.setStoplossTicks(-200000, -190000);
        (bool canExec, ) = resolver.checker();
        assertEq(canExec, true);
    }

    function test_checker_Success2False() public {
        //no position
        vault.setHasPosition(false);
        (bool canExec, bytes memory execPayload) = resolver.checker();
        assertEq(canExec, false);

        vault.setHasPosition(true);

        (, int24 _currentTick, , , , , ) = pool.slot0();
        int24 _twap = pool.getTwap();
        console2.log("currentTick", _currentTick.toString());
        console2.log("twap", _twap.toString());
        //currentTick -204714
        //twap -204714

        //both in range
        vault.setStoplossTicks(-206280, -203160);
        (canExec, execPayload) = resolver.checker();
        assertEq(canExec, false);

        _swap(false, 100_000 * 1e6);
        //currentTick -204610
        //twap -204714

        //current is in and twap is out
        vault.setStoplossTicks(-204620, -204600);
        (canExec, execPayload) = resolver.checker();
        assertEq(canExec, false);

        //current is out and twap is in
        vault.setStoplossTicks(-204720, -204710);
        (canExec, execPayload) = resolver.checker();
        assertEq(canExec, false);
    }

    function _swap(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        ISwapRouter.ExactInputSingleParams memory inputParams;
        if (_zeroForOne) {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: 3000,
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
                fee: 3000,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        }
        amountOut_ = router.exactInputSingle(inputParams);
    }
}

contract OrangeAlphaVaultMockForResolver {
    IUniswapV3Pool public pool;
    int24 public stoplossLowerTick;
    int24 public stoplossUpperTick;
    bool public hasPosition = true;

    constructor(address _pool) {
        pool = IUniswapV3Pool(_pool);
    }

    function setStoplossTicks(int24 _stoplossLowerTick, int24 _stoplossUpperTick) external {
        stoplossLowerTick = _stoplossLowerTick;
        stoplossUpperTick = _stoplossUpperTick;
    }

    function setHasPosition(bool _hasPosition) external {
        hasPosition = _hasPosition;
    }

    function totalAssets() external pure returns (uint256) {
        return 100000;
    }
}
