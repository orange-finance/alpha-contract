// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

library UniswapRouterSwapper {
    ///@notice Swap exact amount in
    function swapAmountIn(
        ISwapRouter router,
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn
    ) internal returns (uint256 amountOut_) {
        if (_amountIn == 0) return 0;

        ISwapRouter.ExactInputSingleParams memory _params = ISwapRouter.ExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: _fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        amountOut_ = router.exactInputSingle(_params);
    }

    ///@notice Swap exact amount out
    function swapAmountOut(
        ISwapRouter router,
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountOut
    ) internal returns (uint256 amountIn_) {
        if (_amountOut == 0) return 0;

        ISwapRouter.ExactOutputSingleParams memory _params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            fee: _fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: 0
        });
        amountIn_ = router.exactOutputSingle(_params);
    }
}
