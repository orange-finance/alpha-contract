// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";
import {IOrangeVaultV1} from "../interfaces/IOrangeVaultV1.sol";
import {IUniswapV3LiquidityPoolManager} from "../interfaces/IUniswapV3LiquidityPoolManager.sol";
//libraries
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../libs/uniswap/OracleLibrary.sol";

contract OrangeStrategyV1 {
    using FullMath for uint256;

    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    /* ========== STORAGES ========== */

    /* ========== PARAMETERS ========== */
    IOrangeVaultV1 public vault;
    IUniswapV3LiquidityPoolManager public liquidityPool;
    address public token0; //collateral and deposited currency by users
    address public token1; //debt and hedge target token
    IOrangeAlphaParameters public params;

    /* ========== MODIFIER ========== */

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault, address _params) {
        // setting adresses and approving
        vault = IOrangeVaultV1(_vault);
        token0 = address(vault.token0());
        token1 = address(vault.token1());
        liquidityPool = vault.liquidityPool();
        params = IOrangeAlphaParameters(_params);
    }

    /**
     * @notice get simuldated liquidity if rebalanced
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _newStoplossUpperTick The new upper bound of the position's range
     * @param _hedgeRatio hedge ratio
     * @return liquidity_ amount of liquidity
     */
    function getRebalancedLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio
    ) external view returns (uint128 liquidity_) {
        uint256 _assets = vault.totalAssets();
        uint256 _ltv = _getLtvByRange(_newStoplossUpperTick);
        IOrangeVaultV1.Positions memory _position = _computeRebalancePosition(
            _assets,
            _newLowerTick,
            _newUpperTick,
            _ltv,
            _hedgeRatio
        );

        //compute liquidity
        liquidity_ = liquidityPool.getLiquidityForAmounts(
            _newLowerTick,
            _newUpperTick,
            _position.token0Balance,
            _position.token1Balance
        );
    }

    function _quoteAtTick(
        int24 _tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256) {
        return OracleLibrary.getQuoteAtTick(_tick, baseAmount, baseToken, quoteToken);
    }

    function _quoteCurrent(uint128 baseAmount, address baseToken, address quoteToken) internal view returns (uint256) {
        (, int24 _tick, , , , , ) = liquidityPool.pool().slot0();
        return _quoteAtTick(_tick, baseAmount, baseToken, quoteToken);
    }

    function computeRebalancePosition(
        uint256 _assets0,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) external view returns (IOrangeVaultV1.Positions memory position_) {
        position_ = _computeRebalancePosition(_assets0, _lowerTick, _upperTick, _ltv, _hedgeRatio);
    }

    /// @notice Compute the amount of collateral/debt and token0/token1 to Liquidity
    function _computeRebalancePosition(
        uint256 _assets0,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal view returns (IOrangeVaultV1.Positions memory position_) {
        if (_assets0 == 0) return IOrangeVaultV1.Positions(0, 0, 0, 0);

        // compute ETH/USDC amount ration to add liquidity
        (uint256 _amount0, uint256 _amount1) = liquidityPool.getAmountsForLiquidity(
            _lowerTick,
            _upperTick,
            1e18 //any amount
        );
        uint256 _amount1ValueInToken0 = _quoteCurrent(uint128(_amount1), token1, token0);

        if (_hedgeRatio == 0) {
            position_.token1Balance = (_amount1ValueInToken0 + _amount0 == 0)
                ? 0
                : _assets0.mulDiv(_amount0, (_amount1ValueInToken0 + _amount0));
            position_.token1Balance = (_amount0 == 0) ? 0 : position_.token0Balance.mulDiv(_amount1, _amount0);
        } else {
            //compute collateral/asset ratio
            uint256 _x = (_amount1ValueInToken0 == 0) ? 0 : MAGIC_SCALE_1E8.mulDiv(_amount0, _amount1ValueInToken0);
            uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
                _ltv +
                MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
                MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio).mulDiv(_x, MAGIC_SCALE_1E8);

            //Collateral
            position_.collateralAmount0 = (_collateralRatioReciprocal == 0)
                ? 0
                : _assets0.mulDiv(MAGIC_SCALE_1E8, _collateralRatioReciprocal);

            uint256 _borrow0 = position_.collateralAmount0.mulDiv(_ltv, MAGIC_SCALE_1E8);
            //borrowing usdc amount to weth
            position_.debtAmount1 = _quoteCurrent(uint128(_borrow0), token0, token1);

            // amount added on Uniswap
            position_.token1Balance = position_.debtAmount1.mulDiv(MAGIC_SCALE_1E8, _hedgeRatio);
            position_.token0Balance = (_amount1 == 0) ? 0 : position_.token1Balance.mulDiv(_amount0, _amount1);
        }
    }

    function getLtvByRange(int24 _upperTick) external view returns (uint256 ltv_) {
        ltv_ = _getLtvByRange(_upperTick);
    }

    ///@notice Get LTV by current and range prices
    ///@dev called by _computeRebalancePosition. maxLtv * (current price / upper price)
    function _getLtvByRange(int24 _upperTick) internal view returns (uint256 ltv_) {
        // any amount is right because we only need the ratio
        uint256 _currentPrice = _quoteCurrent(1 ether, token0, token1);
        uint256 _upperPrice = _quoteAtTick(_upperTick, 1 ether, token0, token1);
        ltv_ = params.maxLtv();
        if (_currentPrice < _upperPrice) {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
        }
    }
}
