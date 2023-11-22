// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title ILiquidityPoolCollectable
 * @author Orange Finance
 * @notice Interface for the Liquidity Pool that is compatible with Performance Fee.
 * We currently assume that the pool is Uniswap V3 Pool or Camelot V3 Pool.
 */
interface ILiquidityPoolCollectable {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    function burn(int24 tickLower, int24 tickUpper, uint128 amount) external;
}

/**
 * @title PerformanceFee
 * @notice A library that provides functions to collect performance fee from Uniswap V3 Pool or Camelot V3 Pool.
 */
library PerformanceFee {
    using SafeERC20 for IERC20;

    /**
     * @notice Parameters for collecting performance fee.
     * @param lowerTick The lower tick of the range to collect fees on.
     * @param upperTick The upper tick of the range to collect fees on.
     * @param perfFeeDivisor The divisor to calculate performance fee.
     * @param perfFeeRecipient The recipient of performance fee.
     */
    struct FeeCollectParams {
        int24 lowerTick;
        int24 upperTick;
        uint128 perfFeeDivisor;
        address perfFeeRecipient;
    }

    /// @notice Collects performance fee from the pool.
    function takeFee(ILiquidityPoolCollectable pool, FeeCollectParams memory params) internal {
        address perfFeeRecipient = params.perfFeeRecipient;
        uint128 perfFeeDivisor = params.perfFeeDivisor;
        int24 lowerTick = params.lowerTick;
        int24 upperTick = params.upperTick;

        // if no recipient, skip
        if (perfFeeRecipient == address(0)) return;
        // if divisor set to zero, skip
        if (perfFeeDivisor == 0) return;

        // zero burn to update feeGrowth
        pool.burn(lowerTick, upperTick, 0);

        (uint128 _amount0, uint128 _amount1) = pool.collect(
            msg.sender,
            lowerTick,
            upperTick,
            type(uint128).max,
            type(uint128).max
        );

        IERC20 _token0 = IERC20(pool.token0());
        IERC20 _token1 = IERC20(pool.token1());

        (uint128 _perfFee0, uint128 _perfFee1) = (_amount0 / perfFeeDivisor, _amount1 / perfFeeDivisor);

        if (_perfFee0 > 0 && _token0.balanceOf(msg.sender) >= _perfFee0)
            _token0.safeTransferFrom(msg.sender, perfFeeRecipient, _perfFee0);

        if (_perfFee1 > 0 && _token1.balanceOf(msg.sender) >= _perfFee1)
            _token1.safeTransferFrom(msg.sender, perfFeeRecipient, _perfFee1);
    }
}
