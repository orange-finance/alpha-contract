// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOrangeAlphaVault {
    /* ========== STRUCTS ========== */

    ///@dev this struct only used in memory
    struct Ticks {
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
    }

    ///@dev this struct only used in memory
    struct Balances {
        uint256 balance0;
        uint256 balance1;
    }

    ///@dev this struct only used in memory and interfaces
    struct UnderlyingAssets {
        uint256 amount0Current;
        uint256 amount1Current;
        uint256 accruedFees0;
        uint256 accruedFees1;
        uint256 amount0Balance;
        uint256 amount1Balance;
    }

    /* ========== EVENTS ========== */

    event BurnAndCollectFees(
        uint256 burn0,
        uint256 burn1,
        uint256 fee0,
        uint256 fee1
    );

    /**
     * @notice actionTypes
     * 0. executed manually
     * 1. deposit
     * 2. redeem
     * 3. rebalance
     * 4. stoploss
     */
    event Action(
        uint8 indexed actionType,
        address indexed caller,
        uint256 totalAssets,
        uint256 totalSupply
    );

    /* ========== VIEW FUNCTIONS ========== */

    function stoplossLowerTick() external view returns (int24);

    function stoplossUpperTick() external view returns (int24);

    function pool() external view returns (IUniswapV3Pool pool);

    function token1() external view returns (IERC20 token1);

    /**
     * @notice get total assets
     * @return totalManagedAssets
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @notice convert assets to shares(shares is the amount of vault token)
     * @param assets amount of assets
     * @return shares
     */
    function convertToShares(uint256 assets)
        external
        view
        returns (uint256 shares);

    /**
     * @notice convert shares to assets
     * @param shares amount of vault token
     * @return assets
     */
    function convertToAssets(uint256 shares)
        external
        view
        returns (uint256 assets);

    /**
     * @notice get underlying assets
     * @return underlyingAssets amount0Current, amount1Current, accruedFees0, accruedFees1, amount0Balance, amount1Balance
     */
    function getUnderlyingBalances()
        external
        view
        returns (UnderlyingAssets memory underlyingAssets);

    /**
     * @notice get simuldated liquidity if rebalanced
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _newStoplossLowerTick The new lower bound of the position's range
     * @param _newStoplossUpperTick The new upper bound of the position's range
     * @return liquidity_ amount of liquidity
     */
    function getRebalancedLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick
    ) external view returns (uint128 liquidity_);

    /**
     * @notice whether can stoploss
     * @param _currentTick current tick
     * @param _lowerTick lower tick
     * @param _upperTick upper tick
     * @return bool whether can stoploss
     */
    function canStoploss(
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick
    ) external view returns (bool);

    /* ========== EXTERNAL FUNCTIONS ========== */
    /**
     * @notice deposit assets and get vault token
     * @param assets amount of assets
     * @param _receiver receiver address
     * @param minShares minimum amount of returned vault token
     * @return shares
     */
    function deposit(
        uint256 assets,
        address _receiver,
        uint256 minShares
    ) external returns (uint256 shares);

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
     * @notice emit action event
     */
    function emitAction() external;

    /**
     * @notice Remove all positions only when current price is out of range
     * @param inputTick Input tick for slippage checking
     */
    function stoploss(int24 inputTick) external;

    /**
     * @notice Remove all positions
     * @param inputTick Input tick for slippage checking
     */
    function removeAllPosition(int24 inputTick) external;

    /**
     * @notice Change the range of underlying UniswapV3 position
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _newStoplossLowerTick The new lower bound of the stoploss range
     * @param _newStoplossUpperTick The new upper bound of the stoploss range
     * @param _minNewLiquidity minimum liqidiity
     */
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint128 _minNewLiquidity
    ) external;
}
