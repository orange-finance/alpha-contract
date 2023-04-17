// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOrangeAlphaVault {
    enum ActionType {
        MANUAL,
        DEPOSIT,
        REDEEM,
        REBALANCE,
        STOPLOSS
    }

    enum FlashloanType {
        DEPOSIT,
        REDEEM
    }

    /* ========== STRUCTS ========== */

    struct Ticks {
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
    }

    struct Balances {
        uint256 balance0;
        uint256 balance1;
    }

    struct Positions {
        uint256 debtAmount0; //debt amount of token0 on Lending
        uint256 collateralAmount1; //collateral amount of token1 on Lending
        uint256 token0Balance; //balance of token0
        uint256 token1Balance; //balance of token1
    }

    struct UnderlyingAssets {
        uint256 liquidityAmount0; //liquidity amount of token0 on Uniswap
        uint256 liquidityAmount1; //liquidity amount of token1 on Uniswap
        uint256 accruedFees0; //fees of token0 on Uniswap
        uint256 accruedFees1; //fees of token1 on Uniswap
        uint256 token0Balance; //balance of token0
        uint256 token1Balance; //balance of token1
    }

    /* ========== EVENTS ========== */

    event BurnAndCollectFees(uint256 burn0, uint256 burn1, uint256 fee0, uint256 fee1);

    event Action(ActionType indexed actionType, address indexed caller, uint256 totalAssets, uint256 totalSupply);

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Get true if having the position of Uniswap
    function hasPosition() external view returns (bool);

    /// @notice Get the stoploss range
    function stoplossLowerTick() external view returns (int24);

    /// @notice Get the stoploss range
    function stoplossUpperTick() external view returns (int24);

    /// @notice Get the pool address
    function pool() external view returns (IUniswapV3Pool pool);

    /// @notice Get the token1 address
    function token1() external view returns (IERC20 token1);

    /**
     * @notice convert assets to shares(shares is the amount of vault token)
     * @param assets amount of assets
     * @return shares
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice convert shares to assets
     * @param shares amount of vault token
     * @return assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice get total assets
     * @return totalManagedAssets
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @notice get underlying assets
     * @return underlyingAssets amount0Current, amount1Current, accruedFees0, accruedFees1, amount0Balance, amount1Balance
     */
    function getUnderlyingBalances() external view returns (UnderlyingAssets memory underlyingAssets);

    /**
     * @notice get simuldated liquidity if rebalanced
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _newStoplossLowerTick The new lower bound of the position's range
     * @param _newStoplossUpperTick The new upper bound of the position's range
     * @param _hedgeRatio hedge ratio
     * @return liquidity_ amount of liquidity
     */
    function getRebalancedLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio
    ) external view returns (uint128 liquidity_);

    /* ========== EXTERNAL FUNCTIONS ========== */
    /**
     * @notice deposit assets and get vault token
     * @param _shares amount of vault token
     * @param _receiver receiver address
     * @param _maxAssets maximum amount of assets
     * @return shares
     */
    function deposit(uint256 _shares, address _receiver, uint256 _maxAssets) external returns (uint256 shares);

    /**
     * @notice redeem vault token to assets
     * @param shares amount of vault token
     * @param receiver receiver address
     * @param owner owner address
     * @param minAssets minimum amount of returned assets
     * @return assets
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAssets
    ) external returns (uint256 assets);

    /**
     * @notice Remove all positions only when current price is out of range
     * @param inputTick Input tick for slippage checking
     * @param _minFinalBalance minimum final balance
     * @return finalBalance_ balance of USDC after removing all positions
     */
    function stoploss(int24 inputTick, uint256 _minFinalBalance) external returns (uint256 finalBalance_);

    /**
     * @notice Change the range of underlying UniswapV3 position
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _newStoplossLowerTick The new lower bound of the stoploss range
     * @param _newStoplossUpperTick The new upper bound of the stoploss range
     * @param _hedgeRatio hedge ratio in 1e8 (100% = 1e8)
     * @param _minNewLiquidity minimum liqidiity
     */
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio,
        uint128 _minNewLiquidity
    ) external;

    /**
     * @notice emit action event
     */
    function emitAction() external;
}
