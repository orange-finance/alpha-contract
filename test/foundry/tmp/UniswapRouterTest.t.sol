// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract UniswapRouterTest is BaseTest {
    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    using SafeERC20 for IERC20;

    ISwapRouter router;
    IERC20 weth;
    IERC20 usdc;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        router = ISwapRouter(uniswapAddr.routerAddr);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);

        deal(tokenAddr.wethAddr, address(this), 10_000 ether);
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        weth.safeApprove(address(router), type(uint256).max);
        usdc.safeApprove(address(router), type(uint256).max);
    }

    function test_swapSingle() public {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
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
}
