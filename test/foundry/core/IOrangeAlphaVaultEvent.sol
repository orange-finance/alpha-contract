// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";

interface IOrangeAlphaVaultEvent {
    /* ========== EVENTS ========== */
    event Redeem(
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 withdrawnCollateral,
        uint256 repaid,
        uint128 liquidityBurned
    );

    event Rebalance(
        int24 lowerTick_,
        int24 upperTick_,
        uint128 liquidityBefore,
        uint128 liquidityAfter
    );

    event RemoveAllPosition(
        uint128 liquidity,
        uint256 withdrawingCollateral,
        uint256 repayingDebt
    );

    event UpdateDepositCap(uint256 depositCap, uint256 totalDepositCap);
    event UpdateSlippage(uint16 slippageBPS, uint24 tickSlippageBPS);
    event UpdateMaxLtv(uint32 maxLtv);

    event SwapAndAddLiquidity(
        bool zeroForOne,
        int256 amount0Delta,
        int256 amount1Delta,
        uint128 liquidity,
        uint256 amountDeposited0,
        uint256 amountDeposited1
    );

    event BurnAndCollectFees(
        uint256 burn0,
        uint256 burn1,
        uint256 fee0,
        uint256 fee1
    );

    event Action(
        uint8 indexed actionType,
        address indexed caller,
        uint256 amount0Debt,
        uint256 amount1Supply,
        IOrangeAlphaVault.UnderlyingAssets underlyingAssets,
        uint256 totalAssets,
        uint256 totalSupply,
        uint256 lowerPrice,
        uint256 upperPrice,
        uint256 currentPrice
    );
}
