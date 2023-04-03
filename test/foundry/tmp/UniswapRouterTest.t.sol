// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract UniswapRouterTest is BaseTest {
    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    using SafeERC20 for IERC20;

    ISwapRouter router;
    IUniswapV3Pool public pool;
    IERC20 weth;
    IERC20 usdc;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        router = ISwapRouter(uniswapAddr.routerAddr);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);

        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        weth.safeApprove(address(router), type(uint256).max);
        usdc.safeApprove(address(router), type(uint256).max);
    }

    function test_exactInputSingle() public {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: 10 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactInputSingle` executes the swap.
        uint256 amountOut = router.exactInputSingle(params);
        console2.log(amountOut, "amountOut");
    }

    function test_exactOutputSingle() public {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: 12000 * 1e6,
            amountInMaximum: 10 ether,
            sqrtPriceLimitX96: 0
        });

        // The call to `exactInputSingle` executes the swap.
        uint256 amountIn = router.exactOutputSingle(params);
        console2.log(amountIn, "amountIn");
    }

    function test_exactInputSingle_Slippage() public {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: 10 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: _sqrtRatioX96
        });

        // The call to `exactInputSingle` executes the swap.
        vm.expectRevert(bytes("SPL"));
        router.exactInputSingle(params);

        params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: 10 ether,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: (_sqrtRatioX96 * 9900) / 10000
        });

        uint256 amountOut = router.exactInputSingle(params);
        console2.log(amountOut, "amountOut");
    }

    function test_exactOutputSingle_Slippage() public {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: 12000 * 1e6,
            amountInMaximum: 10 ether,
            sqrtPriceLimitX96: _sqrtRatioX96
        });

        // The call to `exactInputSingle` executes the swap.
        vm.expectRevert(bytes("SPL"));
        router.exactOutputSingle(params);

        params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            fee: 3000,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: 12000 * 1e6,
            amountInMaximum: 10 ether,
            sqrtPriceLimitX96: (_sqrtRatioX96 * 9900) / 10000
        });
        uint256 amountIn = router.exactOutputSingle(params);
        console2.log(amountIn, "amountIn");
    }
}
