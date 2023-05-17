// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeVaultV1TestBase.sol";
import {OrangeStrategyImplV1} from "../../../contracts/coreV1/OrangeStrategyImplV1.sol";

contract OrangeStrategyImplV1MockTest is OrangeVaultV1TestBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    OrangeStrategyImplV1Caller caller;
    OrangeStrategyImplV1Callee callee;

    function setUp() public override {
        super.setUp();
        callee = new OrangeStrategyImplV1Callee();
        caller = new OrangeStrategyImplV1Caller(address(callee), address(router), address(token0));
        token0.transfer(address(caller), 1e18);

        console2.log("router", address(router));
        console2.log("callee", address(callee));
        console2.log("caller", address(caller));
        console2.log("this", address(this));
    }

    function test() public {
        caller.swapAmountOut(address(router), address(token0), address(token1), 1e6);
    }
}

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

contract OrangeStrategyImplV1Caller is Proxy {
    address impl;

    constructor(address _impl, address router, address tokenIn) {
        impl = _impl;
        IERC20(tokenIn).approve(router, type(uint256).max);
    }

    function _implementation() internal view override returns (address) {
        return impl;
    }

    function swapAmountOut(address, address, address, uint256) external returns (uint256) {
        _delegate(impl);
    }
}

contract OrangeStrategyImplV1Callee {
    function swapAmountOut(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 _amountOut
    ) external returns (uint256 amountIn_) {
        ISwapRouter.ExactOutputSingleParams memory _params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 500,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: 0
        });
        amountIn_ = ISwapRouter(router).exactOutputSingle(_params);
    }
}
