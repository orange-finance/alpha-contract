// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {Ownable} from "../libs/Ownable.sol";
import {Errors} from "../libs/Errors.sol";
import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {IResolver} from "../vendor/gelato/IResolver.sol";
import {GelatoOps} from "../vendor/gelato/GelatoOps.sol";
import {IAaveV3Pool} from "../interfaces/IAaveV3Pool.sol";
import {DataTypes} from "../vendor/aave/DataTypes.sol";
import {TickMath} from "../vendor/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "../vendor/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../vendor/uniswap/OracleLibrary.sol";

import "forge-std/console2.sol";
import {Ints} from "../mocks/Ints.sol";

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

contract OrangeAlphaVault is
    IOrangeAlphaVault,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    ERC20,
    Ownable,
    IResolver,
    GelatoOps
{
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;

    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== STORAGES ========== */
    /// @inheritdoc IOrangeAlphaVault
    mapping(address => DepositType) public override deposits;
    /// @inheritdoc IOrangeAlphaVault
    uint256 public override totalDeposits;
    bool public stoplossed;
    int24 public lowerTick;
    int24 public upperTick;

    IUniswapV3Pool public pool;
    IERC20 public token0; //weth
    IERC20 public token1; //usdc
    IAaveV3Pool public aave;
    IERC20 public debtToken0; //weth
    IERC20 public aToken1; //usdc
    uint8 _decimal;

    /* ========== PARAMETERS ========== */
    uint256 _depositCap;
    /// @inheritdoc IOrangeAlphaVault
    uint256 public override totalDepositCap;
    uint16 public slippageBPS;
    uint24 public tickSlippageBPS;
    uint32 public twapSlippageInterval;
    uint32 public maxLtv;
    uint40 public lockupPeriod;
    address public rebalancer;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 __decimal,
        address _pool,
        address _token0,
        address _token1,
        address _aave,
        address _debtToken0,
        address _aToken1,
        int24 _lowerTick,
        int24 _upperTick
    ) ERC20(_name, _symbol) {
        _decimal = __decimal;

        // setting adresses and approving
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        token0.safeApprove(_pool, type(uint256).max);
        token1.safeApprove(_pool, type(uint256).max);

        aave = IAaveV3Pool(_aave);
        debtToken0 = IERC20(_debtToken0);
        aToken1 = IERC20(_aToken1);
        token0.safeApprove(_aave, type(uint256).max);
        token1.safeApprove(_aave, type(uint256).max);

        // these variables can be udpated by the manager
        _depositCap = 1_000_000 * 1e6;
        totalDepositCap = 1_000_000 * 1e6;
        slippageBPS = 500; // default: 5% slippage
        tickSlippageBPS = 10;
        twapSlippageInterval = 5 minutes;
        maxLtv = 80000000; //80%
        lockupPeriod = 7 days;
        rebalancer = msg.sender;

        //setting ticks
        _validateTicks(_lowerTick, _upperTick);
        lowerTick = _lowerTick;
        upperTick = _upperTick;
    }

    /* ========== VIEW FUNCTIONS ========== */
    /// @inheritdoc IOrangeAlphaVault
    /// @dev share is propotion of liquidity. Caluculate hedge position and liquidity position except for hedge position.
    function convertToShares(uint256 _assets)
        external
        view
        returns (uint256 shares_)
    {
        Ticks memory _ticks = _getTicksByStorage();
        if (
            !stoplossed &&
            !_isOutOfRange(
                _ticks.currentTick,
                _ticks.lowerTick,
                _ticks.upperTick
            )
        ) {
            uint128 _liquidity = _computeNewLiquidity(_assets, _ticks);
            //calculate mint amount
            if (totalDeposits == 0) {
                //if initial depositing, shares = _liquidity
                shares_ = _liquidity;
            } else {
                uint256 _totalLiquidity = _getCurrentLiquidity(_ticks);
                shares_ = totalSupply().mulDiv(_liquidity, _totalLiquidity);
            }
        } else {
            //when stoplossed or out of range
            //shares is propotion of token0 balance
            if (totalDeposits == 0) {
                shares_ = 0;
            } else {
                uint256 _balance = token1.balanceOf(address(this));
                shares_ = totalSupply().mulDiv(_assets, _balance);
            }
        }
    }

    function _computeNewLiquidity(uint256 _assets, Ticks memory _ticks)
        internal
        view
        returns (uint128 liquidity_)
    {
        // 2. Supply USDC(Collateral)
        (uint256 _supply, uint256 _borrow) = _computeSupplyAndBorrow(
            _assets,
            _ticks
        );
        console2.log(_supply, "_supply");
        console2.log(_borrow, "_borrow");

        uint256 _addingUsdc = _assets - _supply;
        (bool _zeroForOne, int256 _swapAmount) = _computeSwapAmount(
            _borrow,
            _addingUsdc,
            _ticks
        );

        if (_zeroForOne) {
            uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
                _ticks.currentTick,
                SafeCast.toUint128(uint256(_swapAmount)),
                address(token0),
                address(token1)
            );
            _borrow -= SafeCast.toUint128(uint256(_swapAmount));
            _addingUsdc += quoteAmount;
        } else {
            uint256 quoteAmount = OracleLibrary.getQuoteAtTick(
                _ticks.currentTick,
                SafeCast.toUint128(uint256(_swapAmount)),
                address(token1),
                address(token0)
            );
            _borrow += quoteAmount;
            _addingUsdc -= SafeCast.toUint128(uint256(_swapAmount));
        }
        console2.log(_borrow, "_borrow");
        console2.log(_addingUsdc, "_addingUsdc");

        liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.sqrtRatioX96,
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _borrow,
            _addingUsdc
        );
        console2.log(liquidity_, "liquidity_");
    }

    /// @inheritdoc IOrangeAlphaVault
    function convertToAssets(uint256 _shares) external view returns (uint256) {
        return _convertToAssets(_shares, _getTicksByStorage());
    }

    /// @inheritdoc IOrangeAlphaVault
    function totalAssets() external view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return _totalAssets(_getTicksByStorage());
    }

    // /// @inheritdoc IOrangeAlphaVault
    function computeNewLiquidity(int24 _newLowerTick, int24 _newUpperTick)
        external
        view
        returns (uint128 liquidity_)
    {
        Ticks memory _ticks = _getTicksByStorage();
        uint256 _totalAssets = _totalAssets(_ticks);
        _ticks.lowerTick = _newLowerTick;
        _ticks.upperTick = _newUpperTick;
        liquidity_ = _computeNewLiquidity(_totalAssets, _ticks);
    }

    ///@notice external function of _getUnderlyingBalances
    function getUnderlyingBalances()
        external
        view
        returns (UnderlyingAssets memory underlyingAssets)
    {
        return _getUnderlyingBalances(_getTicksByStorage());
    }

    ///@notice external function of _computeSupplyAndBorrow
    function computeSupplyAndBorrow(uint256 _assets)
        external
        view
        returns (uint256 supply_, uint256 borrow_)
    {
        return _computeSupplyAndBorrow(_assets, _getTicksByStorage());
    }

    ///@notice external function of _getLtvByRange
    function getLtvByRange() external view returns (uint256) {
        return _getLtvByRange(_getTicksByStorage());
    }

    ///@notice external function of _computeSwapAmount
    function computeSwapAmount(uint256 _amount0, uint256 _amount1)
        external
        view
        returns (bool _zeroForOne, int256 _swapAmount)
    {
        return _computeSwapAmount(_amount0, _amount1, _getTicksByStorage());
    }

    /// @inheritdoc IOrangeAlphaVault
    function depositCap(address) public view returns (uint256) {
        return _depositCap;
    }

    ///@notice external function of _getPositionID
    function getPositionID() public view returns (bytes32 positionID) {
        return _getPositionID(lowerTick, upperTick);
    }

    ///@notice external function of _getTicksByStorage
    function getTicksByStorage() external view returns (Ticks memory) {
        return _getTicksByStorage();
    }

    // @inheritdoc ERC20
    function checker()
        external
        view
        override
        returns (bool canExec, bytes memory execPayload)
    {
        Ticks memory _ticks = _getTicksByStorage();
        if (_canStoploss(_ticks, _getTwap())) {
            execPayload = abi.encodeWithSelector(
                IOrangeAlphaVault.stoploss.selector,
                _ticks.currentTick
            );
            return (true, execPayload);
        } else {
            return (false, bytes("can not stoploss"));
        }
    }

    // @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _decimal;
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    function _getCurrentLiquidity(Ticks memory _ticks)
        internal
        view
        returns (uint128 liquidity_)
    {
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(
            _ticks
        );

        uint256 amount0Current = _underlyingAssets.amount0Current +
            _underlyingAssets.accruedFees0 +
            _underlyingAssets.amount0Balance;
        uint256 amount1Current = _underlyingAssets.amount1Current +
            _underlyingAssets.accruedFees1 +
            _underlyingAssets.amount1Balance;

        //compute liquidity
        liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(_ticks.lowerTick),
            TickMath.getSqrtRatioAtTick(_ticks.upperTick),
            amount0Current,
            amount1Current
        );
    }

    ///@notice internal function of totalAssets
    function _totalAssets(Ticks memory _ticks) internal view returns (uint256) {
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(
            _ticks
        );

        // Aave positions
        uint256 amount0Debt = debtToken0.balanceOf(address(this));
        uint256 amount1Supply = aToken1.balanceOf(address(this));

        return
            _alignTotalAsset(
                _ticks,
                _underlyingAssets.amount0Current +
                    _underlyingAssets.accruedFees0 +
                    _underlyingAssets.amount0Balance,
                _underlyingAssets.amount1Current +
                    _underlyingAssets.accruedFees1 +
                    _underlyingAssets.amount1Balance,
                amount0Debt,
                amount1Supply
            );
    }

    ///@notice internal function of convertToAssets
    function _convertToAssets(uint256 _shares, Ticks memory _ticks)
        public
        view
        returns (uint256 assets)
    {
        uint256 supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        return
            supply == 0
                ? _shares
                : _shares.mulDiv(_totalAssets(_ticks), supply);
    }

    /**
     * @notice Compute total asset price as USDC
     * @dev Align WETH (amount0Current and amount0Debt) to USDC
     * amount0Current + amount1Current - amount0Debt + amount1Supply
     * @param _ticks current and range ticks
     * @param amount0Current amount of underlying token0
     * @param amount1Current amount of underlying token1
     * @param amount0Debt amount of debt
     * @param amount1Supply amount of collateral
     */
    function _alignTotalAsset(
        Ticks memory _ticks,
        uint256 amount0Current,
        uint256 amount1Current,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) internal view returns (uint256 totalAlignedAssets) {
        if (amount0Current < amount0Debt) {
            uint256 amount0deducted = amount0Debt - amount0Current;
            amount0deducted = OracleLibrary.getQuoteAtTick(
                _ticks.currentTick,
                uint128(amount0deducted),
                address(token0),
                address(token1)
            );
            totalAlignedAssets =
                amount1Current +
                amount1Supply -
                amount0deducted;
        } else {
            uint256 amount0Added = amount0Current - amount0Debt;
            if (amount0Added > 0) {
                amount0Added = OracleLibrary.getQuoteAtTick(
                    _ticks.currentTick,
                    uint128(amount0Added),
                    address(token0),
                    address(token1)
                );
            }
            totalAlignedAssets = amount1Current + amount1Supply + amount0Added;
        }
    }

    /**
     * @notice Get the amount of underlying assets
     * The assets includes added liquidity, fees and left amount in this vault
     * @dev similar to Arrakis'
     * @param _ticks current and range ticks
     * @return underlyingAssets
     */
    function _getUnderlyingBalances(Ticks memory _ticks)
        internal
        view
        returns (UnderlyingAssets memory underlyingAssets)
    {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(_getPositionID(_ticks.lowerTick, _ticks.upperTick));

        // compute current holdings from liquidity
        if (liquidity > 0) {
            (
                underlyingAssets.amount0Current,
                underlyingAssets.amount1Current
            ) = LiquidityAmounts.getAmountsForLiquidity(
                _ticks.sqrtRatioX96,
                _ticks.lowerTick.getSqrtRatioAtTick(),
                _ticks.upperTick.getSqrtRatioAtTick(),
                liquidity
            );
        }

        underlyingAssets.accruedFees0 =
            _computeFeesEarned(true, feeGrowthInside0Last, liquidity, _ticks) +
            uint256(tokensOwed0);
        underlyingAssets.accruedFees1 =
            _computeFeesEarned(false, feeGrowthInside1Last, liquidity, _ticks) +
            uint256(tokensOwed1);

        underlyingAssets.amount0Balance = token0.balanceOf(address(this));
        underlyingAssets.amount1Balance = token1.balanceOf(address(this));
    }

    /**
     * @notice Compute one of fee amount
     * @dev similar to Arrakis'
     * @param isZero The side of pairs, true for token0, false is token1
     * @param feeGrowthInsideLast last fee growth
     * @param liquidity liqudity amount
     * @param _ticks current and range ticks
     * @return fee
     */
    function _computeFeesEarned(
        bool isZero,
        uint256 feeGrowthInsideLast,
        uint128 liquidity,
        Ticks memory _ticks
    ) internal view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        if (isZero) {
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(
                _ticks.lowerTick
            );
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(
                _ticks.upperTick
            );
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(
                _ticks.lowerTick
            );
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(
                _ticks.upperTick
            );
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (_ticks.currentTick >= _ticks.lowerTick) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (_ticks.currentTick < _ticks.upperTick) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal -
                feeGrowthBelow -
                feeGrowthAbove;
            fee = FullMath.mulDiv(
                liquidity,
                feeGrowthInside - feeGrowthInsideLast,
                0x100000000000000000000000000000000
            );
        }
    }

    /**
     * @notice Compute collateral and borrow amount
     * @param _assets The amount of assets
     * @param _ticks current and range ticks
     * @return supply_
     * @return borrow_
     */
    function _computeSupplyAndBorrow(uint256 _assets, Ticks memory _ticks)
        internal
        view
        returns (uint256 supply_, uint256 borrow_)
    {
        if (_assets == 0) return (0, 0);

        uint256 _currentLtv = _getLtvByRange(_ticks);

        supply_ = _assets.mulDiv(
            MAGIC_SCALE_1E8,
            _currentLtv + MAGIC_SCALE_1E8
        );
        uint256 _borrowUsdc = supply_.mulDiv(_currentLtv, MAGIC_SCALE_1E8);
        //borrowing usdc amount to weth
        borrow_ = OracleLibrary.getQuoteAtTick(
            _ticks.currentTick,
            uint128(_borrowUsdc),
            address(token1),
            address(token0)
        );
    }

    /**
     * @notice Get LTV by current and range prices
     * @dev maxLtv * (current price / upper price)
     * @param _ticks current and range ticks
     * @return ltv_
     */
    function _getLtvByRange(Ticks memory _ticks)
        internal
        view
        returns (uint256 ltv_)
    {
        uint256 _currentPrice = _quoteEthPriceByTick(_ticks.currentTick);
        uint256 _lowerPrice = _quoteEthPriceByTick(_ticks.lowerTick);
        uint256 _upperPrice = _quoteEthPriceByTick(_ticks.upperTick);

        ltv_ = maxLtv;
        if (_currentPrice > _upperPrice) {
            // ltv_ = maxLtv;
        } else if (_currentPrice < _lowerPrice) {
            ltv_ = ltv_.mulDiv(_lowerPrice, _upperPrice);
        } else {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
        }
    }

    /**
     * @notice Compute swapping amount after judge which token be swapped.
     * Calculate both tokens amounts by liquidity, larger token will be swapped
     * @param _amount0 The amount of token0
     * @param _amount1 The amount of token1
     * @param _ticks current and range ticks
     * @return _zeroForOne
     * @return _swapAmount
     */
    function _computeSwapAmount(
        uint256 _amount0,
        uint256 _amount1,
        Ticks memory _ticks
    ) internal view returns (bool _zeroForOne, int256 _swapAmount) {
        if (_amount0 == 0 && _amount1 == 0) return (false, 0);

        //compute swapping direction and amount
        uint128 _liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
            _ticks.sqrtRatioX96,
            _ticks.upperTick.getSqrtRatioAtTick(),
            _amount0
        );
        uint128 _liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.sqrtRatioX96,
            _amount1
        );

        if (_liquidity0 > _liquidity1) {
            _zeroForOne = true;
            (uint256 _mintAmount0, ) = LiquidityAmounts.getAmountsForLiquidity(
                _ticks.sqrtRatioX96,
                _ticks.lowerTick.getSqrtRatioAtTick(),
                _ticks.upperTick.getSqrtRatioAtTick(),
                _liquidity1
            );
            uint256 _surplusAmount = _amount0 - _mintAmount0;
            //compute how much amount should be swapped by price rate
            _swapAmount = SafeCast.toInt256(
                (_surplusAmount * _computePercentageFromUpperRange(_ticks)) /
                    MAGIC_SCALE_1E8
            );
        } else {
            (, uint256 _mintAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                _ticks.sqrtRatioX96,
                _ticks.lowerTick.getSqrtRatioAtTick(),
                _ticks.upperTick.getSqrtRatioAtTick(),
                _liquidity0
            );
            uint256 _surplusAmount = _amount1 - _mintAmount1;
            _swapAmount = SafeCast.toInt256(
                (_surplusAmount *
                    (MAGIC_SCALE_1E8 -
                        _computePercentageFromUpperRange(_ticks))) /
                    MAGIC_SCALE_1E8
            );
        }
    }

    /**
     * @notice Get Uniswap's position ID
     * @param _lowerTick The lower tick
     * @param _upperTick The upper tick
     * @return positionID
     */
    function _getPositionID(int24 _lowerTick, int24 _upperTick)
        internal
        view
        returns (bytes32 positionID)
    {
        return
            keccak256(abi.encodePacked(address(this), _lowerTick, _upperTick));
    }

    /**
     * @notice Can stoploss when not stopplossed and out of range
     * @return
     */
    function _canStoploss(Ticks memory _ticks, int24 _avgTick)
        internal
        view
        returns (bool)
    {
        return (!stoplossed &&
            _isOutOfRange(
                _ticks.currentTick,
                _ticks.lowerTick,
                _ticks.upperTick
            ) &&
            _isOutOfRange(_avgTick, _ticks.lowerTick, _ticks.upperTick));
    }

    /**
     * @notice Stopped loss executed or current tick out of range
     * @param _tick current tick
     * @param _lowerTick The lower tick
     * @param _upperTick The upper tick
     * @return
     */
    function _isOutOfRange(
        int24 _tick,
        int24 _lowerTick,
        int24 _upperTick
    ) internal pure returns (bool) {
        return (_tick > _upperTick || _tick < _lowerTick);
    }

    /**
     * @notice Cheking tickSpacing
     * @param _lowerTick The lower tick
     * @param _upperTick The upper tick
     */
    function _validateTicks(int24 _lowerTick, int24 _upperTick) internal view {
        int24 _spacing = pool.tickSpacing();
        if (
            _lowerTick < _upperTick &&
            _lowerTick % _spacing == 0 &&
            _upperTick % _spacing == 0
        ) {
            return;
        }
        revert(Errors.TICKS);
    }

    /**
     * @notice Quote eth price by USDC
     * @param _tick target ticks
     * @return ethPrice
     */
    function _quoteEthPriceByTick(int24 _tick) internal view returns (uint256) {
        return
            OracleLibrary.getQuoteAtTick(
                _tick,
                1 ether,
                address(token0),
                address(token1)
            );
    }

    /**
     * @notice Get ticks from this storage and Uniswap
     * @dev access storage of this and Uniswap
     * Storage access should be minimized from gas cost point of view
     * @return ticks
     */
    function _getTicksByStorage() internal view returns (Ticks memory) {
        (uint160 _sqrtRatioX96, int24 _tick, , , , , ) = pool.slot0();
        return Ticks(_sqrtRatioX96, _tick, lowerTick, upperTick);
    }

    /**
     * @notice Get ticks from this storage and Uniswap
     * @dev similar Arrakis'
     * @param _currentSqrtRatioX96 Current sqrt ratio
     * @param _zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
     * @return _swapThresholdPrice
     */
    function _checkSlippage(uint160 _currentSqrtRatioX96, bool _zeroForOne)
        internal
        view
        returns (uint160 _swapThresholdPrice)
    {
        if (_zeroForOne) {
            return
                uint160(
                    FullMath.mulDiv(
                        _currentSqrtRatioX96,
                        slippageBPS,
                        MAGIC_SCALE_1E4
                    )
                );
        } else {
            return
                uint160(
                    FullMath.mulDiv(
                        _currentSqrtRatioX96,
                        MAGIC_SCALE_1E4 + slippageBPS,
                        MAGIC_SCALE_1E4
                    )
                );
        }
    }

    function _checkTickSlippage(int24 _inputTick, int24 _currentTick)
        internal
        view
    {
        if (
            _currentTick > _inputTick + int24(tickSlippageBPS) ||
            _currentTick < _inputTick - int24(tickSlippageBPS)
        ) {
            revert(Errors.HIGH_SLIPPAGE);
        }
    }

    function _getTwap() internal view virtual returns (int24 avgTick) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = twapSlippageInterval;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgo);

        require(tickCumulatives.length == 2, "array len");
        unchecked {
            avgTick = int24(
                (tickCumulatives[1] - tickCumulatives[0]) /
                    int56(uint56(twapSlippageInterval))
            );
        }
    }

    /**
     * @notice computing percentage of (upper price - current price) / (upper price - lower price)
     *  e.g. upper price: 1100, lower price: 900
     *  if current price is 1000,return 50%. if 1050,return 25%. if 1100,return 0%. if 900,return 100%
     * @param _ticks current and range ticks
     * @return parcentageFromUpper_
     */
    function _computePercentageFromUpperRange(Ticks memory _ticks)
        internal
        view
        returns (uint256 parcentageFromUpper_)
    {
        uint256 _currentPrice = _quoteEthPriceByTick(_ticks.currentTick);
        uint256 _lowerPrice = _quoteEthPriceByTick(_ticks.lowerTick);
        uint256 _upperPrice = _quoteEthPriceByTick(_ticks.upperTick);

        uint256 _maxPriceRange = _upperPrice - _lowerPrice;
        uint256 _currentPriceFromUpper;
        if (_currentPrice > _upperPrice) {
            //_currentPriceFromUpper = 0
        } else if (_currentPrice < _lowerPrice) {
            _currentPriceFromUpper = _maxPriceRange;
        } else {
            _currentPriceFromUpper = _upperPrice - _currentPrice;
        }
        parcentageFromUpper_ =
            (MAGIC_SCALE_1E8 * _currentPriceFromUpper) /
            _maxPriceRange;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    /// @inheritdoc IOrangeAlphaVault
    function deposit(
        uint256 _shares,
        address _receiver,
        uint256 _maxAssets
    ) external returns (uint256 assets_) {
        //validation
        if (_receiver != msg.sender) {
            revert(Errors.DEPOSIT_RECEIVER);
        }
        if (_shares == 0 || _maxAssets == 0) revert(Errors.ZERO);
        console2.log(depositCap(_receiver), "depositCap(_receiver)");
        if (deposits[_receiver].assets + _maxAssets > depositCap(_receiver)) {
            revert(Errors.CAPOVER);
        }
        deposits[_receiver].assets += _maxAssets;
        deposits[_receiver].timestamp = uint40(block.timestamp);
        uint256 _totalDeposits = totalDeposits;
        if (_totalDeposits + _maxAssets > totalDepositCap) {
            revert(Errors.CAPOVER);
        }

        Ticks memory _ticks = _getTicksByStorage();
        if (
            !stoplossed &&
            !_isOutOfRange(
                _ticks.currentTick,
                _ticks.lowerTick,
                _ticks.upperTick
            )
        ) {
            // 1. Transfer USDC from depositer to Vault
            token1.safeTransferFrom(msg.sender, address(this), _maxAssets);

            //compute liquidity
            uint128 _liquidity;
            if (_totalDeposits == 0) {
                //if initial depositing, shares = _liquidity
                _liquidity = SafeCast.toUint128(_shares);
            } else {
                uint256 _totalLiquidity = _getCurrentLiquidity(_ticks);
                _liquidity = SafeCast.toUint128(
                    _totalLiquidity.mulDiv(_shares, totalSupply())
                );
            }

            uint256 _balance1 = _depositInRange(_liquidity, _maxAssets, _ticks);

            // 6. Return suplus amount
            console2.log("6. return suplus amount");
            if (_balance1 > 0) {
                token1.safeTransfer(msg.sender, _balance1);
            }
            assets_ = _maxAssets - _balance1;
        } else {
            //when stoplossed or out of range
            //calculate mint amount
            if (_totalDeposits == 0) {
                revert(Errors.DEPOSIT_STOPLOSSED);
            } else {
                // 1. Transfer USDC from depositer to Vault
                uint256 _balance = token1.balanceOf(address(this));
                assets_ = _balance.mulDiv(_shares, totalSupply());
                if (assets_ > _maxAssets) {
                    revert(Errors.MORE);
                }
                token1.safeTransferFrom(msg.sender, address(this), assets_);
            }
        }

        //mint
        _mint(_receiver, _shares);
        totalDeposits = _totalDeposits + _maxAssets;

        _emitAction(1, _ticks);
    }

    function _depositInRange(
        uint128 _liquidity,
        uint256 _maxAssets,
        Ticks memory _ticks
    ) internal returns (uint256 balance1_) {
        // 2. Compute amounts by shares
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                _ticks.sqrtRatioX96,
                _ticks.lowerTick.getSqrtRatioAtTick(),
                _ticks.upperTick.getSqrtRatioAtTick(),
                _liquidity
            );
        console2.log(_amount0, "_amount0");
        console2.log(_amount1, "_amount1");

        // 3. Compute supply and borrow
        (uint256 _supply, uint256 _borrow) = _computeSupplyAndBorrow(
            _maxAssets,
            _ticks
        );

        // 4. Supply USDC(Collateral) and Borrow ETH
        if (_supply > 0) {
            aave.supply(address(token1), _supply, address(this), 0);
        }
        if (_borrow > 0) {
            aave.borrow(address(token0), _borrow, 2, 0, address(this));
        }

        // Swap (if necessary)
        uint256 _balance0 = _borrow;
        balance1_ = _maxAssets - _supply;
        console2.log("balance.token0", token0.balanceOf(address(this)));
        console2.log("balance.token1", token1.balanceOf(address(this)));
        (_balance0, balance1_, _ticks) = _swapInDeposit(
            _balance0,
            balance1_,
            _amount0,
            _amount1,
            _ticks
        );

        // 5. Add liquidity
        if (_liquidity > 0) {
            console2.log("mint0");
            console2.log("balance.token0", token0.balanceOf(address(this)));
            console2.log("balance.token1", token1.balanceOf(address(this)));
            (uint256 _amountDeposited0, uint256 _amountDeposited1) = pool.mint(
                address(this),
                _ticks.lowerTick,
                _ticks.upperTick,
                _liquidity,
                ""
            );
            console2.log("mint1");
            if (
                _amountDeposited0 > _balance0 || _amountDeposited1 > balance1_
            ) {
                revert(Errors.MORE);
            }
            _balance0 -= _amountDeposited0;
            balance1_ -= _amountDeposited1;
        }

        // 6. return suplus amount
        // if token0(ETH) is left, swap it to USDC
        if (_balance0 > 0) {
            console2.log(_balance0, "_balance0");
            console2.log(token0.balanceOf(address(this)), "token0.balanceOf");
            (, int256 _amount1Delta) = pool.swap(
                address(this),
                true,
                SafeCast.toInt256(_balance0),
                _checkSlippage(_ticks.sqrtRatioX96, true),
                ""
            );
            balance1_ = uint256(SafeCast.toInt256(balance1_) - _amount1Delta);
        }
    }

    function _swapInDeposit(
        uint256 _balance0,
        uint256 _balance1,
        uint256 _amount0,
        uint256 _amount1,
        Ticks memory _ticks
    )
        internal
        returns (
            uint256 balance0_,
            uint256 balance1_,
            Ticks memory ticks_
        )
    {
        ticks_ = _ticks;
        balance0_ = _balance0;
        balance1_ = _balance1;
        bool _zeroForOne;
        int256 _swapAmount;
        if (balance1_ < _amount1) {
            console2.log("balance1_ < _amount1");
            //swap ETH to USDC because of lack of USDC
            _zeroForOne = true;
            _swapAmount = SafeCast.toInt256(
                ((_balance0 - _amount0) * 9000) / MAGIC_SCALE_1E4
            ); //if swap all balance, shortage will occur because of tick change
        } else if (balance0_ < _amount0) {
            console2.log("balance0_ < _amount0");
            //swap USDC to ETH because of lack of ETH
            _swapAmount = SafeCast.toInt256(
                ((_balance1 - _amount1) * 9000) / MAGIC_SCALE_1E4
            ); //if swap all balance, shortage will occur because of tick change
        }
        if (_swapAmount > 0) {
            console2.log("_swapAmount > 0");
            (int256 _amount0Delta, int256 _amount1Delta) = pool.swap(
                address(this),
                _zeroForOne,
                _swapAmount,
                _checkSlippage(ticks_.sqrtRatioX96, _zeroForOne),
                ""
            );
            _ticks = _getTicksByStorage(); //retrieve ticks
            balance0_ = uint256(SafeCast.toInt256(balance0_) - _amount0Delta);
            balance1_ = uint256(SafeCast.toInt256(balance1_) - _amount1Delta);
        }
    }

    /// @inheritdoc IOrangeAlphaVault
    function redeem(
        uint256 _shares,
        address _receiver,
        address,
        uint256 _minAssets
    ) external returns (uint256) {
        //validation
        if (_shares == 0) {
            revert(Errors.ZERO);
        }
        if (block.timestamp < deposits[msg.sender].timestamp + lockupPeriod) {
            revert(Errors.LOCKUP);
        }

        uint256 _totalSupply = totalSupply();
        Ticks memory _ticks = _getTicksByStorage();

        //burn
        _burn(msg.sender, _shares);

        // 1. Remove liquidity
        // 2. Collect fees
        (uint256 _assets0, uint256 _assets1, ) = _burnShare(
            _shares,
            _totalSupply,
            _ticks
        );

        // 3. Swap from USDC to ETH (if necessary)
        uint256 _repayingDebt = FullMath.mulDiv(
            _shares,
            debtToken0.balanceOf(address(this)),
            _totalSupply
        );
        if (_assets0 < _repayingDebt) {
            (int256 amount0Delta, int256 amount1Delta) = pool.swap(
                address(this),
                false, //token1 to token0
                SafeCast.toInt256(_assets1),
                _checkSlippage(_ticks.sqrtRatioX96, false),
                ""
            );
            _ticks = _getTicksByStorage(); //retrieve ticks
            _assets0 = uint256(SafeCast.toInt256(_assets0) - amount0Delta);
            _assets1 = uint256(SafeCast.toInt256(_assets1) - amount1Delta);
        }

        // 4. Repay ETH
        if (_repayingDebt > 0) {
            if (
                _repayingDebt !=
                aave.repay(address(token0), _repayingDebt, 2, address(this))
            ) revert(Errors.AAVE_MISMATCH);
            _assets0 -= _repayingDebt;
        }

        // 5. Withdraw USDC as collateral
        uint256 _withdrawingCollateral = FullMath.mulDiv(
            _shares,
            aToken1.balanceOf(address(this)),
            _totalSupply
        );
        if (_withdrawingCollateral > 0) {
            if (
                _withdrawingCollateral !=
                aave.withdraw(
                    address(token1),
                    _withdrawingCollateral,
                    address(this)
                )
            ) revert(Errors.AAVE_MISMATCH);
            _assets1 += _withdrawingCollateral;
        }

        // 6. Swap from ETH to USDC (if necessary)
        if (_assets0 > 0) {
            (int256 amount0Delta, int256 amount1Delta) = pool.swap(
                address(this),
                true, //token0 to token1
                SafeCast.toInt256(_assets0),
                _checkSlippage(_ticks.sqrtRatioX96, true),
                ""
            );
            _ticks = _getTicksByStorage(); //retrieve ticks
            _assets0 = uint256(SafeCast.toInt256(_assets0) - amount0Delta);
            _assets1 = uint256(SafeCast.toInt256(_assets1) - amount1Delta);
        }

        // 7. Transfer USDC from Vault to Pool
        if (_minAssets > _assets1) {
            revert(Errors.LESS);
        }
        token1.safeTransfer(_receiver, _assets1);

        //subtract deposits
        uint256 _deposited = deposits[_receiver].assets;
        if (_deposited < _assets1) {
            deposits[_receiver].assets = 0;
        } else {
            deposits[_receiver].assets -= _assets1;
        }
        if (totalDeposits < _assets1) {
            totalDeposits = 0;
        } else {
            totalDeposits -= _assets1;
        }

        _emitAction(2, _ticks);
        return _assets1;
    }

    /// @inheritdoc IOrangeAlphaVault
    function emitAction() external {
        _emitAction(0, _getTicksByStorage());
    }

    /// @inheritdoc IOrangeAlphaVault
    function stoploss(int24 _inputTick) external onlyDedicatedMsgSender {
        Ticks memory _ticks = _getTicksByStorage();
        _stoploss(_ticks, _inputTick);
    }

    /* ========== OWNERS FUNCTIONS ========== */

    /// @inheritdoc IOrangeAlphaVault
    /// @dev similar to Arrakis' executiveRebalance
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        uint128 _minNewLiquidity
    ) external {
        if (rebalancer != msg.sender) {
            revert(Errors.REBALANCER);
        }

        // 1. Check tickSpacing
        _validateTicks(_newLowerTick, _newUpperTick);

        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            lowerTick = _newLowerTick;
            upperTick = _newUpperTick;
            return;
        }

        Ticks memory _ticks = _getTicksByStorage();

        // 2. Remove liquidity
        // 3. Collect fees
        (uint128 liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        if (liquidity > 0) {
            _burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick, liquidity);
        }
        lowerTick = _newLowerTick;
        upperTick = _newUpperTick;
        _ticks.lowerTick = _newLowerTick;
        _ticks.upperTick = _newUpperTick;

        //calculate repay or borrow amount
        (uint256 _newSupply, uint256 _newBorrow) = _computeSupplyAndBorrow(
            _totalAssets(_ticks),
            _ticks
        );
        console2.log(_newSupply, "_newSupply");
        console2.log(_newBorrow, "_newBorrow");

        //after stoploss, need to supply collateral
        uint256 _supplyBalance = aToken1.balanceOf(address(this));
        if (_supplyBalance < _newSupply) {
            aave.supply(
                address(token1),
                _newSupply - _supplyBalance,
                address(this),
                0
            );
        }

        // 4. Swap
        // 5. Repay or borrow (if swapping from ETH to USDC, do borrow)
        uint256 _debtBalance = debtToken0.balanceOf(address(this));
        if (_debtBalance == _newBorrow) {
            //do nothing
        } else if (_debtBalance > _newBorrow) {
            //swap and repay
            uint256 _repayingDebt = _debtBalance - _newBorrow;
            if (_repayingDebt > token0.balanceOf(address(this))) {
                pool.swap(
                    address(this),
                    false, //token1 to token0
                    SafeCast.toInt256(token1.balanceOf(address(this))),
                    _checkSlippage(_ticks.sqrtRatioX96, false),
                    ""
                );
                _ticks = _getTicksByStorage(); //retrieve ticks
            }
            if (
                _repayingDebt !=
                aave.repay(address(token0), _repayingDebt, 2, address(this))
            ) revert(Errors.AAVE_MISMATCH);
        } else {
            //borrow
            aave.borrow(
                address(token0),
                _newBorrow - _debtBalance,
                2,
                0,
                address(this)
            );
        }

        // 6. Add liquidity
        uint256 reinvest0 = token0.balanceOf(address(this));
        uint256 reinvest1 = token1.balanceOf(address(this));
        console2.log(reinvest0, "reinvest0");
        console2.log(reinvest1, "reinvest1");
        _swapAndAddLiquidity(reinvest0, reinvest1, _ticks);

        (uint128 newLiquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        console2.log("newLiquidity", newLiquidity);
        console2.log("_minNewLiquidity", _minNewLiquidity);
        if (newLiquidity < _minNewLiquidity) {
            revert(Errors.LESS);
        }

        emit Rebalance(_newLowerTick, _newUpperTick, liquidity, newLiquidity);
        _emitAction(3, _ticks);

        //reset stoplossed
        stoplossed = false;
    }

    /// @inheritdoc IOrangeAlphaVault
    function removeAllPosition(int24 _inputTick) external onlyOwner {
        Ticks memory _ticks = _getTicksByStorage();
        _ticks = _removeAllPosition(_ticks, _inputTick);
        _emitAction(5, _ticks);
    }

    /**
     * @notice Set parameters of depositCap
     * @param __depositCap Deposit cap of each accounts
     * @param _totalDepositCap Total deposit cap
     */
    function setDepositCap(uint256 __depositCap, uint256 _totalDepositCap)
        external
        onlyOwner
    {
        if (__depositCap > _totalDepositCap) {
            revert(Errors.PARAMS);
        }
        _depositCap = __depositCap;
        totalDepositCap = _totalDepositCap;
        emit UpdateDepositCap(__depositCap, _totalDepositCap);
    }

    /**
     * @notice Set parameters of slippage
     * @param _slippageBPS Slippage BPS
     * @param _tickSlippageBPS Check ticks BPS
     */
    function setSlippage(uint16 _slippageBPS, uint24 _tickSlippageBPS)
        external
        onlyOwner
    {
        if (_slippageBPS > MAGIC_SCALE_1E4) {
            revert(Errors.PARAMS);
        }
        slippageBPS = _slippageBPS;
        tickSlippageBPS = _tickSlippageBPS;
        emit UpdateSlippage(_slippageBPS, _tickSlippageBPS);
    }

    /**
     * @notice Set parameters of max LTV
     * @param _maxLtv Max LTV
     */
    function setMaxLtv(uint32 _maxLtv) external onlyOwner {
        if (_maxLtv > MAGIC_SCALE_1E8) {
            revert(Errors.PARAMS);
        }
        maxLtv = _maxLtv;
        emit UpdateMaxLtv(_maxLtv);
    }

    /**
     * @notice Set parameters of lockup period
     * @param _twapSlippageInterval TWAP slippage interval
     */
    function setTwapSlippageInterval(uint32 _twapSlippageInterval)
        external
        onlyOwner
    {
        twapSlippageInterval = _twapSlippageInterval;
    }

    /**
     * @notice Set parameters of lockup period
     * @param _lockupPeriod Lockup period
     */
    function setLockupPeriod(uint40 _lockupPeriod) external onlyOwner {
        lockupPeriod = _lockupPeriod;
    }

    /**
     * @notice Set parameters of Rebalancer
     * @param _rebalancer Rebalancer
     */
    function setRebalancer(address _rebalancer) external onlyOwner {
        rebalancer = _rebalancer;
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */

    /**
     * @notice Swap surplus amount of larger token and add liquidity
     * @dev similar to _deposit on Arrakis
     * @param _amount0 The amount of token0
     * @param _amount1 The amount of token1
     * @param _ticks current and range ticks
     * @return liquidity_
     * @return amountDeposited0_
     * @return amountDeposited1_
     */
    function _swapAndAddLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        Ticks memory _ticks
    )
        internal
        returns (
            uint128 liquidity_,
            uint256 amountDeposited0_,
            uint256 amountDeposited1_
        )
    {
        if (_amount0 == 0 && _amount1 == 0)
            revert(Errors.ADD_LIQUIDITY_AMOUNTS);

        (bool _zeroForOne, int256 _swapAmount) = _computeSwapAmount(
            _amount0,
            _amount1,
            _ticks
        );

        //swap
        int256 amount0Delta;
        int256 amount1Delta;
        if (_swapAmount != 0) {
            (amount0Delta, amount1Delta) = pool.swap(
                address(this),
                _zeroForOne,
                _swapAmount,
                _checkSlippage(_ticks.sqrtRatioX96, _zeroForOne),
                ""
            );
            _ticks = _getTicksByStorage(); //retrieve ticks
            //compute liquidity after swapping
            _amount0 = uint256(SafeCast.toInt256(_amount0) - amount0Delta);
            _amount1 = uint256(SafeCast.toInt256(_amount1) - amount1Delta);
        }

        liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.sqrtRatioX96,
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _amount0,
            _amount1
        );

        //mint
        if (liquidity_ > 0) {
            (amountDeposited0_, amountDeposited1_) = pool.mint(
                address(this),
                _ticks.lowerTick,
                _ticks.upperTick,
                liquidity_,
                ""
            );
        }
        emit SwapAndAddLiquidity(
            _zeroForOne,
            amount0Delta,
            amount1Delta,
            liquidity_,
            amountDeposited0_,
            amountDeposited1_
        );
    }

    /**
     * @notice Burn liquidity per share and compute underlying amount per share
     * @dev called by redeem function
     * @param _shares The amount of vault token
     * @param _totalSupply The total amount of vault token
     * @param _ticks current and range ticks
     * @return burnAndFees0_
     * @return burnAndFees1_
     * @return liquidityBurned_
     */
    function _burnShare(
        uint256 _shares,
        uint256 _totalSupply,
        Ticks memory _ticks
    )
        internal
        returns (
            uint256 burnAndFees0_,
            uint256 burnAndFees1_,
            uint128 liquidityBurned_
        )
    {
        (uint128 _liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        liquidityBurned_ = SafeCast.toUint128(
            FullMath.mulDiv(_shares, _liquidity, _totalSupply)
        );

        (
            uint256 _burn0,
            uint256 _burn1,
            uint256 _fee0,
            uint256 _fee1,
            uint256 _preBalance0,
            uint256 _preBalance1
        ) = _burnAndCollectFees(
                _ticks.lowerTick,
                _ticks.upperTick,
                liquidityBurned_
            );
        _fee0 = FullMath.mulDiv(_shares, _fee0, _totalSupply);
        _fee1 = FullMath.mulDiv(_shares, _fee1, _totalSupply);
        _preBalance0 = FullMath.mulDiv(_shares, _preBalance0, _totalSupply);
        _preBalance1 = FullMath.mulDiv(_shares, _preBalance1, _totalSupply);
        burnAndFees0_ = _burn0 + _fee0 + _preBalance0;
        burnAndFees1_ = _burn1 + _fee1 + _preBalance1;
    }

    /**
     * @notice Burn liquidity per share and compute underlying amount per share
     * @dev similar to _withdraw on Arrakis
     * @param _lowerTick The lower tick
     * @param _upperTick The upper tick
     * @param _liquidity The liquidity
     * @return burn0_
     * @return burn1_
     * @return fee0_
     * @return fee1_
     * @return preBalance0_
     * @return preBalance1_
     */
    function _burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    )
        internal
        returns (
            uint256 burn0_,
            uint256 burn1_,
            uint256 fee0_,
            uint256 fee1_,
            uint256 preBalance0_,
            uint256 preBalance1_
        )
    {
        preBalance0_ = token0.balanceOf(address(this));
        preBalance1_ = token1.balanceOf(address(this));

        if (_liquidity > 0) {
            (burn0_, burn1_) = pool.burn(_lowerTick, _upperTick, _liquidity);
        }

        pool.collect(
            address(this),
            _lowerTick,
            _upperTick,
            type(uint128).max,
            type(uint128).max
        );

        fee0_ = token0.balanceOf(address(this)) - preBalance0_ - burn0_;
        fee1_ = token1.balanceOf(address(this)) - preBalance1_ - burn1_;
        emit BurnAndCollectFees(burn0_, burn1_, fee0_, fee1_);
    }

    ///@notice internal function of stoploss
    function _stoploss(Ticks memory _ticks, int24 _inputTick) internal {
        if (!_canStoploss(_ticks, _getTwap())) {
            revert(Errors.WHEN_CAN_STOPLOSS);
        }
        stoplossed = true;
        _ticks = _removeAllPosition(_ticks, _inputTick);
        _emitAction(4, _ticks);
    }

    ///@notice internal function of removeAllPosition
    function _removeAllPosition(Ticks memory _ticks, int24 _inputTick)
        internal
        returns (Ticks memory ticks_)
    {
        if (totalSupply() == 0) {
            return _ticks;
        }

        //check slippage by tick
        _checkTickSlippage(_inputTick, _ticks.currentTick);

        // 1. Remove liquidity
        // 2. Collect fees
        (uint128 liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        if (liquidity > 0) {
            _burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick, liquidity);
        }

        // 3. Swap from USDC to ETH (if necessary)
        uint256 _repayingDebt = debtToken0.balanceOf(address(this));
        if (token0.balanceOf(address(this)) < _repayingDebt) {
            pool.swap(
                address(this),
                false, //token1 to token0
                SafeCast.toInt256(token1.balanceOf(address(this))),
                _checkSlippage(_ticks.sqrtRatioX96, false),
                ""
            );
            _ticks = _getTicksByStorage(); //retrieve ticks
        }

        // 4. Repay ETH
        if (_repayingDebt > 0) {
            if (
                _repayingDebt !=
                aave.repay(address(token0), _repayingDebt, 2, address(this))
            ) revert(Errors.AAVE_MISMATCH);
        }
        // 5. Withdraw USDC as collateral
        uint256 _withdrawingCollateral = aToken1.balanceOf(address(this));
        if (_withdrawingCollateral > 0) {
            if (
                _withdrawingCollateral !=
                aave.withdraw(
                    address(token1),
                    _withdrawingCollateral,
                    address(this)
                )
            ) revert(Errors.AAVE_MISMATCH);
        }

        // swap ETH to USDC
        uint256 _balanceToken0 = token0.balanceOf(address(this));
        if (_balanceToken0 > 0) {
            pool.swap(
                address(this),
                true, //token0 to token1
                SafeCast.toInt256(_balanceToken0),
                _checkSlippage(_ticks.sqrtRatioX96, true),
                ""
            );
            _ticks = _getTicksByStorage(); //retrieve ticks
        }

        emit RemoveAllPosition(
            liquidity,
            _withdrawingCollateral,
            _repayingDebt
        );
        return _ticks;
    }

    ///@notice internal function of emitAction
    function _emitAction(uint8 _actionType, Ticks memory _ticks) internal {
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(
            _ticks
        );

        // Aave positions
        uint256 amount0Debt = debtToken0.balanceOf(address(this));
        uint256 amount1Supply = aToken1.balanceOf(address(this));

        uint256 _alignedAsset = _alignTotalAsset(
            _ticks,
            _underlyingAssets.amount0Current +
                _underlyingAssets.accruedFees0 +
                _underlyingAssets.amount0Balance,
            _underlyingAssets.amount1Current +
                _underlyingAssets.accruedFees1 +
                _underlyingAssets.amount1Balance,
            amount0Debt,
            amount1Supply
        );

        emit Action(
            _actionType,
            msg.sender,
            amount0Debt,
            amount1Supply,
            _underlyingAssets,
            _alignedAsset,
            totalSupply(),
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _ticks.sqrtRatioX96
        );
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    /// @notice Uniswap V3 callback fn, called back on pool.mint
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata /*_data*/
    ) external override {
        if (msg.sender != address(pool)) {
            revert(Errors.CALLBACK_CALLER);
        }

        if (amount0Owed > 0) {
            token0.safeTransfer(msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            token1.safeTransfer(msg.sender, amount1Owed);
        }
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external override {
        if (msg.sender != address(pool)) {
            revert(Errors.CALLBACK_CALLER);
        }

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
