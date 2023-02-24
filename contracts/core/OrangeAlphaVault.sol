// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";
import {IAaveV3Pool} from "../interfaces/IAaveV3Pool.sol";

//extend
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//libraries
import {Errors} from "../libs/Errors.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TickMath} from "../vendor/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "../vendor/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../vendor/uniswap/OracleLibrary.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaVault is
    IOrangeAlphaVault,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    ERC20
{
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    // using Ints for int24;

    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== STORAGES ========== */
    bool public stoplossed;
    int24 public lowerTick;
    int24 public upperTick;
    int24 public stoplossLowerTick;
    int24 public stoplossUpperTick;

    /* ========== PARAMETERS ========== */
    IUniswapV3Pool public pool;
    IERC20 token0; //weth
    IERC20 public token1; //usdc
    IAaveV3Pool public aave;
    IERC20 debtToken0; //weth
    IERC20 aToken1; //usdc
    uint8 _decimal;
    IOrangeAlphaParameters public params;

    /* ========== MODIFIER ========== */
    modifier onlyPeriphery() {
        if (msg.sender != params.periphery()) revert(Errors.NOT_PERIPHERY);
        _;
    }

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
        address _params
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

        params = IOrangeAlphaParameters(_params);
    }

    /* ========== VIEW FUNCTIONS ========== */
    /// @inheritdoc IOrangeAlphaVault
    /// @dev share is propotion of liquidity. Caluculate hedge position and liquidity position except for hedge position.
    function convertToShares(uint256 _assets)
        external
        view
        returns (uint256 shares_)
    {
        uint256 _supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        return
            _supply == 0
                ? _assets
                : _supply.mulDiv(_assets, _totalAssets(_getTicksByStorage()));
    }

    /// @inheritdoc IOrangeAlphaVault
    function convertToAssets(uint256 _shares) external view returns (uint256) {
        uint256 _supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        return
            _supply == 0
                ? _shares
                : _shares.mulDiv(_totalAssets(_getTicksByStorage()), _supply);
    }

    /// @inheritdoc IOrangeAlphaVault
    function totalAssets() external view returns (uint256) {
        if (totalSupply() == 0) {
            return 0;
        }
        return _totalAssets(_getTicksByStorage());
    }

    ///@notice internal function of totalAssets
    function _totalAssets(Ticks memory _ticks) internal view returns (uint256) {
        return
            _alignTotalAsset(
                _ticks,
                _getUnderlyingBalances(_ticks),
                debtToken0.balanceOf(address(this)),
                aToken1.balanceOf(address(this))
            );
    }

    ///@notice external function of _getUnderlyingBalances
    function getUnderlyingBalances()
        external
        view
        returns (UnderlyingAssets memory underlyingAssets)
    {
        return _getUnderlyingBalances(_getTicksByStorage());
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
                _ticks.currentTick.getSqrtRatioAtTick(),
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

    function canStoploss(
        int24 _targetTick,
        int24 _lowerTick,
        int24 _upperTick
    ) external view returns (bool) {
        return _canStoploss(_targetTick, _lowerTick, _upperTick);
    }

    /**
     * @notice Can stoploss when not stopplossed and out of range
     * @return
     */
    function _canStoploss(
        int24 _targetTick,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (bool) {
        return (!stoplossed &&
            (_targetTick > _upperTick || _targetTick < _lowerTick));
    }

    // @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _decimal;
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */

    /**
     * @notice Compute total asset price as USDC
     * @dev Align WETH (amount0Current and amount0Debt) to USDC
     * amount0Current + amount1Current - amount0Debt + amount1Supply
     * @param _ticks current and range ticks
     * @param _underlyingAssets current underlying assets
     * @param amount0Debt amount of debt
     * @param amount1Supply amount of collateral
     */
    function _alignTotalAsset(
        Ticks memory _ticks,
        UnderlyingAssets memory _underlyingAssets,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) internal view returns (uint256 totalAlignedAssets) {
        uint256 amount0Current = _underlyingAssets.amount0Current +
            _underlyingAssets.accruedFees0 +
            _underlyingAssets.amount0Balance;
        uint256 amount1Current = _underlyingAssets.amount1Current +
            _underlyingAssets.accruedFees1 +
            _underlyingAssets.amount1Balance;

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
     * @param _currentTick current  tick
     * @param _lowerTick lower tick
     * @param _upperTick upper tick
     * @return supply_
     * @return borrow_
     */
    function _computeSupplyAndBorrow(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (uint256 supply_, uint256 borrow_) {
        if (_assets == 0) return (0, 0);

        uint256 _currentLtv = _getLtvByRange(
            _currentTick,
            _lowerTick,
            _upperTick
        );
        supply_ = _assets.mulDiv(
            MAGIC_SCALE_1E8,
            _currentLtv + MAGIC_SCALE_1E8
        );
        uint256 _borrowUsdc = supply_.mulDiv(_currentLtv, MAGIC_SCALE_1E8);
        //borrowing usdc amount to weth
        borrow_ = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_borrowUsdc),
            address(token1),
            address(token0)
        );
    }

    /**
     * @notice Get LTV by current and range prices
     * @dev called by _computeSupplyAndBorrow. maxLtv * (current price / upper price)
     * @param _currentTick current tick
     * @param _lowerTick lower tick
     * @param _upperTick upper tick
     * @return ltv_
     */
    function _getLtvByRange(
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (uint256 ltv_) {
        uint256 _currentPrice = _quoteEthPriceByTick(_currentTick);
        uint256 _lowerPrice = _quoteEthPriceByTick(_lowerTick);
        uint256 _upperPrice = _quoteEthPriceByTick(_upperTick);

        ltv_ = params.maxLtv();
        if (_currentPrice > _upperPrice) {
            // ltv_ = maxLtv;
        } else if (_currentPrice < _lowerPrice) {
            ltv_ = ltv_.mulDiv(_lowerPrice, _upperPrice);
        } else {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
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
        (, int24 _tick, , , , , ) = pool.slot0();
        return Ticks(_tick, lowerTick, upperTick);
    }

    /**
     * @notice Get ticks from this storage and Uniswap
     * @dev similar Arrakis'
     * @param _currentSqrtRatioX96 Current sqrt ratio
     * @param _zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
     * @return _swapThresholdPrice
     */
    function _setSlippage(uint160 _currentSqrtRatioX96, bool _zeroForOne)
        internal
        view
        returns (uint160 _swapThresholdPrice)
    {
        // prettier-ignore
        if (_zeroForOne) { 
            return uint160(
                FullMath.mulDiv(
                    _currentSqrtRatioX96,
                    params.slippageBPS(),
                    MAGIC_SCALE_1E4
                )
            );
        } else {
            return uint160(
                FullMath.mulDiv(
                    _currentSqrtRatioX96,
                    MAGIC_SCALE_1E4 + params.slippageBPS(),
                    MAGIC_SCALE_1E4
                )
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
        uint256 _assets,
        address _receiver,
        uint256 _minShares
    ) external onlyPeriphery returns (uint256) {
        //validation check
        if (_assets == 0 || _minShares == 0) revert("ZERO");

        // 1. Transfer USDC from periphery to Vault
        token1.safeTransferFrom(msg.sender, address(this), _assets);

        // if there is no position, mint and return
        if (totalSupply() == 0) {
            _mint(_receiver, _assets);
            return _assets;
        }

        // 2. compute hedge amount and liquidity by shares
        Ticks memory _ticks = _getTicksByStorage();
        (
            uint256 _targetDebtAmount0,
            uint256 _targetCollateralAmount1,
            uint256 _targetAmount0,
            uint256 _targetAmount1
        ) = _computeHedgeAndLiquidity(_minShares, _ticks);

        // 3. swap surplus amount0 or amount1
        Balances memory _balances = Balances(
            _targetDebtAmount0,
            _assets - _targetCollateralAmount1
        );
        _swapSurplusAmount(_balances, _targetAmount0, _targetAmount1, _ticks);

        // 4. execute hedge
        if (_targetCollateralAmount1 > 0) {
            aave.supply(
                address(token1),
                _targetCollateralAmount1,
                address(this),
                0
            );
        }
        if (_targetDebtAmount0 > 0) {
            aave.borrow(
                address(token0),
                _targetDebtAmount0,
                2,
                0,
                address(this)
            );
        }

        // 5. add liquidity
        uint128 _targetLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.currentTick.getSqrtRatioAtTick(),
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _targetAmount0,
            _targetAmount1
        );
        (uint256 _addedAmount0, uint256 _addedAmount1) = pool.mint(
            address(this),
            _ticks.lowerTick,
            _ticks.upperTick,
            _targetLiquidity,
            ""
        );
        _balances.balance0 -= _addedAmount0;
        _balances.balance1 -= _addedAmount1;

        //transfer surplus amount to receiver
        if (_balances.balance0 > 0) {
            token0.safeTransfer(_receiver, _balances.balance0);
        }
        if (_balances.balance1 > 0) {
            token1.safeTransfer(_receiver, _balances.balance1);
        }

        //mint
        _mint(_receiver, _minShares);

        _emitAction(1, _ticks);
        return _minShares;
    }

    function _computeHedgeAndLiquidity(uint256 _minShares, Ticks memory _ticks)
        internal
        view
        returns (
            uint256 _targetDebtAmount0,
            uint256 _targetCollateralAmount1,
            uint256 _targetAmount0,
            uint256 _targetAmount1
        )
    {
        uint256 _totalSupply = totalSupply();

        // compute hedge amount by shares
        _targetDebtAmount0 = debtToken0.balanceOf(address(this)).mulDiv(
            _minShares,
            _totalSupply
        );
        _targetCollateralAmount1 = aToken1.balanceOf(address(this)).mulDiv(
            _minShares,
            _totalSupply
        );

        // compute liquidity amount by shares
        (uint128 liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        uint128 _targetLiquidity = uint128(
            uint256(liquidity).mulDiv(_minShares, _totalSupply)
        );
        (_targetAmount0, _targetAmount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                _ticks.currentTick.getSqrtRatioAtTick(),
                TickMath.getSqrtRatioAtTick(_ticks.lowerTick),
                TickMath.getSqrtRatioAtTick(_ticks.upperTick),
                _targetLiquidity
            );
    }

    //swap surplus amount0 or amount1
    function _swapSurplusAmount(
        Balances memory _balances,
        uint256 _targetAmount0,
        uint256 _targetAmount1,
        Ticks memory _ticks
    ) internal {
        uint256 _surplusAmount0;
        uint256 _surplusAmount1;
        if (_balances.balance0 > _targetAmount0) {
            unchecked {
                _surplusAmount0 = _balances.balance0 - _targetAmount0;
            }
        }
        if (_balances.balance1 > _targetAmount1) {
            unchecked {
                _surplusAmount1 = _balances.balance1 - _targetAmount1;
            }
        }

        if (_surplusAmount0 > 0 && _surplusAmount1 > 0) {
            //no need to swap
        } else if (_surplusAmount0 > 0) {
            //swap amount0 to amount1
            (int256 _amount0Delta, int256 _amount1Delta) = pool.swap(
                address(this),
                true,
                SafeCast.toInt256(_surplusAmount0),
                _setSlippage(_ticks.currentTick.getSqrtRatioAtTick(), true),
                ""
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _balances.balance0 = uint256(
                SafeCast.toInt256(_balances.balance0) - _amount0Delta
            );
            _balances.balance1 = uint256(
                SafeCast.toInt256(_balances.balance1) - _amount1Delta
            );
        } else if (_surplusAmount1 > 0) {
            //swap amount1 to amount0
            (int256 _amount0Delta, int256 _amount1Delta) = pool.swap(
                address(this),
                false,
                SafeCast.toInt256(_surplusAmount1),
                _setSlippage(_ticks.currentTick.getSqrtRatioAtTick(), false),
                ""
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _balances.balance0 = uint256(
                SafeCast.toInt256(_balances.balance0) - _amount0Delta
            );
            _balances.balance1 = uint256(
                SafeCast.toInt256(_balances.balance1) - _amount1Delta
            );
        } else if (_surplusAmount0 == 0 && _surplusAmount1 == 0) {
            revert(Errors.SURPLUS_ZERO);
        }
    }

    /// @inheritdoc IOrangeAlphaVault
    function redeem(
        uint256 _shares,
        address _receiver,
        address,
        uint256 _minAssets
    ) external onlyPeriphery returns (uint256) {
        //validation
        if (_shares == 0) {
            revert(Errors.ZERO);
        }

        uint256 _totalSupply = totalSupply();
        Ticks memory _ticks = _getTicksByStorage();

        //burn
        _burn(_receiver, _shares);

        // 1. Remove liquidity
        // 2. Collect fees
        (uint256 _assets0, uint256 _assets1, ) = _burnShare(
            _shares,
            _totalSupply,
            _ticks
        );

        // 3. Swap from USDC to ETH (if necessary)
        uint256 _repayingDebt = debtToken0.balanceOf(address(this)).mulDiv(
            _shares,
            _totalSupply
        );
        if (_assets0 < _repayingDebt) {
            (int256 amount0Delta, int256 amount1Delta) = pool.swap(
                address(this),
                false, //token1 to token0
                SafeCast.toInt256(_assets1),
                _setSlippage(_ticks.currentTick.getSqrtRatioAtTick(), false),
                ""
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
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
        uint256 _withdrawingCollateral = aToken1
            .balanceOf(address(this))
            .mulDiv(_shares, _totalSupply);
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
            (, int256 amount1Delta) = pool.swap(
                address(this),
                true, //token0 to token1
                SafeCast.toInt256(_assets0),
                _setSlippage(_ticks.currentTick.getSqrtRatioAtTick(), true),
                ""
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _assets1 = uint256(SafeCast.toInt256(_assets1) - amount1Delta);
        }

        // 7. Transfer USDC from Vault to Pool
        if (_minAssets > _assets1) {
            revert(Errors.LESS);
        }
        token1.safeTransfer(_receiver, _assets1);

        _emitAction(2, _ticks);
        return _assets1;
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

    /// @inheritdoc IOrangeAlphaVault
    function emitAction() external {
        _emitAction(0, _getTicksByStorage());
    }

    /// @inheritdoc IOrangeAlphaVault
    function stoploss(int24 _inputTick) external {
        if (params.dedicatedMsgSender() != msg.sender) {
            revert(Errors.DEDICATED_MSG_SENDER);
        }
        Ticks memory _ticks = _getTicksByStorage();
        if (
            !_canStoploss(
                _ticks.currentTick,
                stoplossLowerTick,
                stoplossUpperTick
            )
        ) {
            revert(Errors.WHEN_CAN_STOPLOSS);
        }
        _checkTickSlippage(_ticks.currentTick, _inputTick);

        stoplossed = true;
        _removeAllPosition(_ticks);
        _emitAction(4, _ticks);
    }

    /* ========== OWNERS FUNCTIONS ========== */
    /// @inheritdoc IOrangeAlphaVault
    function removeAllPosition(int24 _inputTick) external {
        if (!params.administrators(msg.sender)) {
            revert(Errors.ADMINISTRATOR);
        }
        Ticks memory _ticks = _getTicksByStorage();
        _checkTickSlippage(_ticks.currentTick, _inputTick);

        _removeAllPosition(_ticks);
        _emitAction(5, _ticks);
    }

    /// @inheritdoc IOrangeAlphaVault
    /// @dev similar to Arrakis' executiveRebalance
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint128 _minNewLiquidity
    ) external {
        if (!params.administrators(msg.sender)) {
            revert(Errors.ADMINISTRATOR);
        }
        //validation of tickSpacing
        _validateTicks(_newLowerTick, _newUpperTick);
        _validateTicks(_newStoplossLowerTick, _newStoplossUpperTick);

        // if there are no position
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            lowerTick = _newLowerTick;
            upperTick = _newUpperTick;
            stoplossLowerTick = _newStoplossLowerTick;
            stoplossUpperTick = _newStoplossUpperTick;
            emit UpdateTicks(
                _newLowerTick,
                _newUpperTick,
                _newStoplossLowerTick,
                _newStoplossUpperTick
            );
            return;
        }

        Ticks memory _ticks = _getTicksByStorage();
        //if not stoplossed, removeAllPosition
        if (!stoplossed) {
            _removeAllPosition(_ticks);
        }

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
        stoplossLowerTick = _newStoplossLowerTick;
        stoplossUpperTick = _newStoplossUpperTick;
        _ticks.lowerTick = _newLowerTick;
        _ticks.upperTick = _newUpperTick;

        //calculate repay or borrow amount
        (uint256 _newSupply, uint256 _newBorrow) = _computeSupplyAndBorrow(
            _totalAssets(_ticks),
            _ticks.currentTick,
            _newStoplossLowerTick,
            _newStoplossUpperTick
        );

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
                    _setSlippage(
                        _ticks.currentTick.getSqrtRatioAtTick(),
                        false
                    ),
                    ""
                );
                (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
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
        (uint128 newLiquidity, , ) = _swapAndAddLiquidity(
            reinvest0,
            reinvest1,
            _ticks
        );

        if (newLiquidity < _minNewLiquidity) {
            revert(Errors.LESS);
        }

        emit UpdateTicks(
            _newLowerTick,
            _newUpperTick,
            _newStoplossLowerTick,
            _newStoplossUpperTick
        );

        _emitAction(3, _ticks);

        //reset stoplossed
        stoplossed = false;
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */

    /**
     * @notice Swap surplus amount of larger token and add liquidity
     * @dev called by rebalance. similar to _deposit on Arrakis
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
                _setSlippage(
                    _ticks.currentTick.getSqrtRatioAtTick(),
                    _zeroForOne
                ),
                ""
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            //compute liquidity after swapping
            _amount0 = uint256(SafeCast.toInt256(_amount0) - amount0Delta);
            _amount1 = uint256(SafeCast.toInt256(_amount1) - amount1Delta);
        }

        liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.currentTick.getSqrtRatioAtTick(),
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
     * @notice Compute swapping amount after judge which token be swapped.
     * Calculate both tokens amounts by liquidity, larger token will be swapped
     * @dev called by _swapAndAddLiquidity
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
            _ticks.currentTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _amount0
        );
        uint128 _liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.currentTick.getSqrtRatioAtTick(),
            _amount1
        );

        if (_liquidity0 > _liquidity1) {
            _zeroForOne = true;
            (uint256 _mintAmount0, ) = LiquidityAmounts.getAmountsForLiquidity(
                _ticks.currentTick.getSqrtRatioAtTick(),
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
                _ticks.currentTick.getSqrtRatioAtTick(),
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

    ///@notice internal function of removeAllPosition
    function _removeAllPosition(Ticks memory _ticks) internal {
        if (totalSupply() == 0) return;

        // 1. Remove liquidity
        // 2. Collect fees
        (uint128 liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        uint256 _fee0;
        uint256 _fee1;
        if (liquidity > 0) {
            (, , _fee0, _fee1, , ) = _burnAndCollectFees(
                _ticks.lowerTick,
                _ticks.upperTick,
                liquidity
            );
        }

        // 3. Swap from USDC to ETH (if necessary)
        uint256 _repayingDebt = debtToken0.balanceOf(address(this));
        if (token0.balanceOf(address(this)) < _repayingDebt) {
            pool.swap(
                address(this),
                false, //token1 to token0
                SafeCast.toInt256(token1.balanceOf(address(this))),
                _setSlippage(_ticks.currentTick.getSqrtRatioAtTick(), false),
                ""
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
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
                _setSlippage(_ticks.currentTick.getSqrtRatioAtTick(), true),
                ""
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
        }

        emit RemoveAllPosition(
            _fee0,
            _fee1,
            liquidity,
            _withdrawingCollateral,
            _repayingDebt
        );
    }

    function _checkTickSlippage(int24 _currentTick, int24 _inputTick)
        internal
        view
    {
        //check slippage by tick
        if (
            _currentTick > _inputTick + int24(params.tickSlippageBPS()) ||
            _currentTick < _inputTick - int24(params.tickSlippageBPS())
        ) {
            revert(Errors.HIGH_SLIPPAGE);
        }
    }

    ///@notice internal function of emitAction
    function _emitAction(uint8 _actionType, Ticks memory _ticks) internal {
        uint256 _alignedAsset = _alignTotalAsset(
            _ticks,
            _getUnderlyingBalances(_ticks),
            debtToken0.balanceOf(address(this)),
            aToken1.balanceOf(address(this))
        );

        emit Action(_actionType, msg.sender, _alignedAsset, totalSupply());
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
