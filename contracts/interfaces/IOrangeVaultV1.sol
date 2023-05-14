// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV3LiquidityPoolManager} from "./IUniswapV3LiquidityPoolManager.sol";
import {IOrangeV1Parameters} from "./IOrangeV1Parameters.sol";

// import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface IOrangeVaultV1Proxy {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        address _poolFactory,
        address _liquidityTemplate,
        address[] memory _liquidityReferences,
        address _lendingTemplate,
        address[] memory _lendingReferences,
        address _params
    ) external;
}

interface IOrangeVaultV1 is IOrangeVaultV1Proxy {
    enum ActionType {
        MANUAL,
        DEPOSIT,
        REDEEM,
        REBALANCE,
        STOPLOSS
    }

    enum FlashloanType {
        DEPOSIT_OVERHEDGE,
        DEPOSIT_UNDERHEDGE,
        REDEEM
    }

    /* ========== STRUCTS ========== */
    struct Positions {
        uint256 collateralAmount0; //collateral amount of token1 on Lending
        uint256 debtAmount1; //debt amount of token0 on Lending
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

    /// @notice Get the token1 address
    function token0() external view returns (IERC20 token0);

    /// @notice Get the token1 address
    function token1() external view returns (IERC20 token1);

    function liquidityPool() external view returns (IUniswapV3LiquidityPoolManager);

    function params() external view returns (IOrangeV1Parameters);

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

    /* ========== EXTERNAL FUNCTIONS ========== */
    /**
     * @notice deposit assets and get vault token
     * @param _shares amount of vault token
     * @param _receiver receiver address
     * @param _maxAssets maximum amount of assets
     * @param _merkleProof merkle proof
     * @return shares
     * @dev increase all position propotionally. e.g. when share = totalSupply, the Vault is doubling up the all position.
     * Position including
     * - Aave USDC Collateral
     * - Aave ETH Debt
     * - Uniswap USDC Liquidity
     * - Uniswap ETH Liquidity
     * - USDC balance in Vault
     * - ETH balance in Vault
     */
    function deposit(
        uint256 _shares,
        address _receiver,
        uint256 _maxAssets,
        bytes32[] calldata _merkleProof
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
     * @notice Remove all positions only when current price is out of range
     * @param inputTick Input tick for slippage checking
     * @return finalBalance_ balance of USDC after removing all positions
     */
    function stoploss(int24 inputTick) external returns (uint256 finalBalance_);

    /**
     * @notice Change the range of underlying UniswapV3 position
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _targetPosition target position
     * @param _minNewLiquidity minimum liqidiity
     */
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        Positions memory _targetPosition,
        uint128 _minNewLiquidity
    ) external;

    /**
     * @notice emit action event
     */
    function emitAction() external;
}
