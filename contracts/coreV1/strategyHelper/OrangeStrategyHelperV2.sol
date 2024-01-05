// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeParametersV1} from "../../interfaces/IOrangeParametersV1.sol";
import {IOrangeVaultV1} from "../../interfaces/IOrangeVaultV1.sol";
import {ILiquidityPoolManager} from "../../interfaces/ILiquidityPoolManager.sol";
import {IResolver} from "../../interfaces/IResolver.sol";

//libraries
import {ErrorsV1} from "../ErrorsV1.sol";
import {UniswapV3Twap, IUniswapV3Pool} from "../../libs/UniswapV3Twap.sol";
import {FullMath} from "../../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../../libs/uniswap/OracleLibrary.sol";

contract OrangeStrategyHelperV2 is IResolver {
    using UniswapV3Twap for IUniswapV3Pool;
    using FullMath for uint256;

    /* ========== CONSTANTS ========== */
    uint256 private constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    /* ========== STORAGE ========== */
    int24 public stoplossLowerTick;
    int24 public stoplossUpperTick;
    mapping(address => bool) public strategists;

    /* ========== PARAMETERS ========== */
    IOrangeVaultV1 public immutable vault;
    address public immutable liquidityPool;
    address public immutable token0; //collateral and deposited currency by users
    address public immutable token1; //debt and hedge target token
    IOrangeParametersV1 public immutable params;

    /* ========== ERRORS =========== */
    error DivisorZero();
    error CTooSmall();

    /* ========== MODIFIER ========== */
    modifier onlyStrategist() {
        if (!strategists[msg.sender]) revert(ErrorsV1.ONLY_STRATEGISTS);
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
        _setStrategist(msg.sender, true);
    }

    /* ========== WRITE FUNCTIONS ========== */
    function setStrategist(address _strategist, bool _status) external onlyStrategist {
        _setStrategist(_strategist, _status);
    }

    function _setStrategist(address _strategist, bool _status) internal {
        strategists[_strategist] = _status;
    }

    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio,
        uint128 _minNewLiquidity
    ) external onlyStrategist {
        // compute target position
        uint256 _ltv = _getLtvByRange(_newStoplossUpperTick);
        IOrangeVaultV1.Positions memory _targetPosition = _computeRebalancePosition(
            vault.totalAssets(),
            _newLowerTick,
            _newUpperTick,
            _ltv,
            _hedgeRatio
        );

        vault.rebalance(_newLowerTick, _newUpperTick, _targetPosition, _minNewLiquidity);

        //update storage
        stoplossLowerTick = _newStoplossLowerTick;
        stoplossUpperTick = _newStoplossUpperTick;
    }

    function stoploss(int24 _inputTick) external onlyStrategist {
        vault.stoploss(_inputTick);
    }

    /* ========== VIEW FUNCTIONS ========== */
    // @inheritdoc IResolver
    function checker() external view virtual override returns (bool, bytes memory) {
        if (vault.hasPosition()) {
            int24 _currentTick = ILiquidityPoolManager(liquidityPool).getCurrentTick();
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
    ) public view returns (uint128 liquidity_) {
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

    function _quoteCurrent(
        uint128 baseAmount,
        address vaultTokenBase,
        address vaultTokenQuote
    ) internal view returns (uint256) {
        int24 _tick = ILiquidityPoolManager(liquidityPool).getCurrentTick();
        bool reversed = ILiquidityPoolManager(liquidityPool).reversed();

        return
            !reversed
                ? _quoteAtTick(_tick, baseAmount, vaultTokenBase, vaultTokenQuote)
                : _quoteAtTick(_tick, baseAmount, vaultTokenQuote, vaultTokenBase);
    }

    /**
     *  @notice Compute the amount of collateral/debt and token0/token1 to Liquidity
     * @param _ltv MAGIC_SCALE_1E8 = 100%
     * @param _hedgeRatio MAGIC_SCALE_1E8 = 100%
     */

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
            1e18 //Arbitrary Liquidity Unit
        );
        uint256 c = MAGIC_SCALE_1E8.mulDiv(MAGIC_SCALE_1E8, _ltv); //1e8
        if (c < MAGIC_SCALE_1E8) revert CTooSmall(); //must be more than 1e8;

        uint256 _token1BalanceInToken0;
        uint256 _debtAmount1InToken0;

        if (_amount0 != 0) {
            uint256 a = MAGIC_SCALE_1E8.mulDiv(_quoteCurrent(uint128(_amount1), token1, token0), _amount0); //1e8

            uint256 divisor = MAGIC_SCALE_1E8 +
                a +
                (a.mulDiv(_hedgeRatio, MAGIC_SCALE_1E8).mulDiv(c, MAGIC_SCALE_1E8)) -
                (a.mulDiv(_hedgeRatio, MAGIC_SCALE_1E8)); //1+a+abc-ab
            if (divisor == 0) revert DivisorZero(); //must not be 0

            position_.token0Balance = _assets0.mulDiv(MAGIC_SCALE_1E8, divisor);
            _token1BalanceInToken0 = position_.token0Balance.mulDiv(a, MAGIC_SCALE_1E8);
        } else {
            //amount0 == 0
            uint256 divisor = MAGIC_SCALE_1E8 + (_hedgeRatio.mulDiv(c, MAGIC_SCALE_1E8)) - _hedgeRatio; //1+bc-b
            if (divisor == 0) revert DivisorZero(); //must not be 0

            position_.token0Balance = 0;
            _token1BalanceInToken0 = _assets0.mulDiv(MAGIC_SCALE_1E8, divisor);
        }
        _debtAmount1InToken0 = _token1BalanceInToken0.mulDiv(_hedgeRatio, MAGIC_SCALE_1E8);
        position_.collateralAmount0 = _debtAmount1InToken0.mulDiv(c, MAGIC_SCALE_1E8);

        position_.token1Balance = _quoteCurrent(uint128(_token1BalanceInToken0), token0, token1);
        position_.debtAmount1 = _quoteCurrent(uint128(_debtAmount1InToken0), token0, token1);
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
