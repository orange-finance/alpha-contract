// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeParametersV1} from "../interfaces/IOrangeParametersV1.sol";
import {IOrangeVaultV1} from "../interfaces/IOrangeVaultV1.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";
import {IResolver} from "../interfaces/IResolver.sol";

//libraries
import {UniswapV3Twap, IUniswapV3Pool} from "../libs/UniswapV3Twap.sol";
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../libs/uniswap/OracleLibrary.sol";

contract OrangeStrategistV1 is IResolver {
    using UniswapV3Twap for IUniswapV3Pool;
    using FullMath for uint256;

    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    /* ========== STORAGE ========== */
    int24 public stoplossLowerTick;
    int24 public stoplossUpperTick;
    mapping(address => bool) operators;

    /* ========== PARAMETERS ========== */
    IOrangeVaultV1 public immutable vault;
    address public immutable liquidityPool;
    address public immutable token0; //collateral and deposited currency by users
    address public immutable token1; //debt and hedge target token
    IOrangeParametersV1 public immutable params;

    /* ========== MODIFIER ========== */
    modifier onlyOperator() {
        require(operators[msg.sender], "ONLY_OPERATOR");
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault) {
        // setting adresses and approving
        vault = IOrangeVaultV1(_vault);
        token0 = address(vault.token0());
        token1 = address(vault.token1());
        liquidityPool = vault.liquidityPool();
        params = IOrangeParametersV1(vault.params());
    }

    /* ========== WRITE FUNCTIONS ========== */
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio,
        uint128 _minNewLiquidity
    ) external onlyOperator {
        if (!params.strategists(msg.sender)) {
            revert("Errors.ONLY_STRATEGISTS");
        }

        // compute target position
        uint256 _ltv = _getLtvByRange(_newStoplossUpperTick);
        IOrangeVaultV1.Positions memory _targetPosition = _computeRebalancePosition(
            vault.totalAssets(),
            _newLowerTick,
            _newUpperTick,
            _ltv,
            _hedgeRatio
        );

        vault.rebalance(
            vault.lowerTick(),
            vault.upperTick(),
            _newLowerTick,
            _newUpperTick,
            _targetPosition,
            _minNewLiquidity
        );

        //update storage
        stoplossLowerTick = _newStoplossLowerTick;
        stoplossUpperTick = _newStoplossUpperTick;
    }

    function stoploss(int24 _inputTick) external onlyOperator {
        vault.stoploss(_inputTick);
    }

    /* ========== VIEW FUNCTIONS ========== */
    // @inheritdoc IResolver
    function checker() external view override returns (bool, bytes memory) {
        if (vault.hasPosition()) {
            (, int24 _currentTick, , , , , ) = ILiquidityPoolManager(liquidityPool).pool().slot0();
            int24 _twap = ILiquidityPoolManager(liquidityPool).getTwap(5 minutes);
            if (
                _isOutOfRange(_currentTick, stoplossLowerTick, stoplossUpperTick) &&
                _isOutOfRange(_twap, stoplossLowerTick, stoplossUpperTick)
            ) {
                bytes memory execPayload = abi.encodeWithSelector(IOrangeVaultV1.stoploss.selector, _twap);
                return (true, execPayload);
            }
        }
        return (false, bytes("ERROR_CANNOT_STOPLOSS"));
    }

    function getRebalancedLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24,
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
        liquidity_ = ILiquidityPoolManager(liquidityPool).getLiquidityForAmounts(
            _newLowerTick,
            _newUpperTick,
            _position.token0Balance,
            _position.token1Balance
        );
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

    function getLtvByRange(int24 _upperTick) external view returns (uint256 ltv_) {
        ltv_ = _getLtvByRange(_upperTick);
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    ///@notice Can stoploss when has position and out of range
    function _isOutOfRange(int24 _targetTick, int24 _lowerTick, int24 _upperTick) internal pure returns (bool) {
        return (_targetTick > _upperTick || _targetTick < _lowerTick);
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
        (, int24 _tick, , , , , ) = ILiquidityPoolManager(liquidityPool).pool().slot0();
        return _quoteAtTick(_tick, baseAmount, baseToken, quoteToken);
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
        (uint256 _amount0, uint256 _amount1) = ILiquidityPoolManager(liquidityPool).getAmountsForLiquidity(
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
