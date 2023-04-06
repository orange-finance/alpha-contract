// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";
import {IAaveFlashLoanSimpleReceiver} from "../interfaces/IAaveFlashLoanSimpleReceiver.sol";

//libraries
import {ERC20} from "../libs/ERC20.sol";
import {SafeAavePool, IAaveV3Pool} from "../libs/SafeAavePool.sol";
import {Errors} from "../libs/Errors.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TickMath} from "../libs/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../libs/uniswap/OracleLibrary.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaVault is IOrangeAlphaVault, IUniswapV3MintCallback, ERC20, IAaveFlashLoanSimpleReceiver {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using SafeAavePool for IAaveV3Pool;
    // using Ints for int24;
    // using Ints for int256;

    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage
    uint16 constant AAVE_REFERRAL_NONE = 0; //for aave
    uint256 constant AAVE_VARIABLE_INTEREST = 2; //for aave

    /* ========== STORAGES ========== */
    bool public hasPosition;
    int24 public lowerTick;
    int24 public upperTick;
    int24 public stoplossLowerTick;
    int24 public stoplossUpperTick;

    /* ========== PARAMETERS ========== */
    IUniswapV3Pool public pool;
    IERC20 public token0; //weth
    IERC20 public token1; //usdc
    ISwapRouter public router;
    IAaveV3Pool public aave;
    IERC20 debtToken0; //weth
    IERC20 aToken1; //usdc
    IOrangeAlphaParameters public params;

    /* ========== MODIFIER ========== */
    modifier onlyPeriphery() {
        if (msg.sender != params.periphery()) revert(Errors.ONLY_PERIPHERY);
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        address _pool,
        address _token0,
        address _token1,
        address _router,
        address _aave,
        address _debtToken0,
        address _aToken1,
        address _params
    ) ERC20(_name, _symbol, 6) {
        // setting adresses and approving
        pool = IUniswapV3Pool(_pool);
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        token0.safeApprove(_pool, type(uint256).max);
        token1.safeApprove(_pool, type(uint256).max);

        router = ISwapRouter(_router);
        token0.safeApprove(_router, type(uint256).max);
        token1.safeApprove(_router, type(uint256).max);

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
    function convertToShares(uint256 _assets) external view returns (uint256 shares_) {
        uint256 _supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _assets : _supply.mulDiv(_assets, _totalAssets(_getTicksByStorage()));
    }

    /// @inheritdoc IOrangeAlphaVault
    function convertToAssets(uint256 _shares) external view returns (uint256) {
        uint256 _supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _shares : _shares.mulDiv(_totalAssets(_getTicksByStorage()), _supply);
    }

    /// @inheritdoc IOrangeAlphaVault
    function totalAssets() external view returns (uint256) {
        if (totalSupply == 0) return 0;
        return _totalAssets(_getTicksByStorage());
    }

    ///@notice internal function of totalAssets
    function _totalAssets(Ticks memory _ticks) internal view returns (uint256 totalAssets_) {
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(_ticks);
        uint256 amount0Debt = debtToken0.balanceOf(address(this));
        uint256 amount1Supply = aToken1.balanceOf(address(this));

        uint256 amount0Balance = _underlyingAssets.liquidityAmount0 +
            _underlyingAssets.accruedFees0 +
            _underlyingAssets.token0Balance;
        uint256 amount1Balance = _underlyingAssets.liquidityAmount1 +
            _underlyingAssets.accruedFees1 +
            _underlyingAssets.token1Balance;
        return _alignTotalAsset(_ticks, amount0Balance, amount1Balance, amount0Debt, amount1Supply);
    }

    /// @notice Compute total asset price as USDC
    /// @dev Underlying Assets - debt + supply called by _totalAssets
    function _alignTotalAsset(
        Ticks memory _ticks,
        uint256 amount0Balance,
        uint256 amount1Balance,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) internal view returns (uint256 totalAlignedAssets) {
        if (amount0Balance < amount0Debt) {
            uint256 amount0deducted = amount0Debt - amount0Balance;
            amount0deducted = OracleLibrary.getQuoteAtTick(
                _ticks.currentTick,
                uint128(amount0deducted),
                address(token0),
                address(token1)
            );
            totalAlignedAssets = amount1Balance + amount1Supply - amount0deducted;
        } else {
            uint256 amount0Added = amount0Balance - amount0Debt;
            if (amount0Added > 0) {
                amount0Added = OracleLibrary.getQuoteAtTick(
                    _ticks.currentTick,
                    uint128(amount0Added),
                    address(token0),
                    address(token1)
                );
            }
            totalAlignedAssets = amount1Balance + amount1Supply + amount0Added;
        }
    }

    /// @inheritdoc IOrangeAlphaVault
    function getUnderlyingBalances() external view returns (UnderlyingAssets memory underlyingAssets) {
        return _getUnderlyingBalances(_getTicksByStorage());
    }

    /// @notice Get the amount of underlying assets
    /// The assets includes added liquidity, fees and left amount in this vault
    /// @dev similar to Arrakis'
    function _getUnderlyingBalances(
        Ticks memory _ticks
    ) internal view returns (UnderlyingAssets memory underlyingAssets) {
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(_getPositionID(_ticks.lowerTick, _ticks.upperTick));

        // compute current holdings from liquidity
        if (liquidity > 0) {
            (underlyingAssets.liquidityAmount0, underlyingAssets.liquidityAmount1) = LiquidityAmounts
                .getAmountsForLiquidity(
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

        underlyingAssets.token0Balance = token0.balanceOf(address(this));
        underlyingAssets.token1Balance = token1.balanceOf(address(this));
    }

    /// @inheritdoc IOrangeAlphaVault
    function getRebalancedLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio
    ) external view returns (uint128 liquidity_) {
        Ticks memory _ticks = _getTicksByStorage();
        uint256 _assets = _totalAssets(_ticks);
        uint256 _ltv = _getLtvByRange(_ticks.currentTick, _newStoplossUpperTick);
        Positions memory _position = _computeRebalancePosition(
            _assets,
            _ticks.currentTick,
            _newLowerTick,
            _newUpperTick,
            _ltv,
            _hedgeRatio
        );

        //compute liquidity
        liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.currentTick.getSqrtRatioAtTick(),
            _newLowerTick.getSqrtRatioAtTick(),
            _newUpperTick.getSqrtRatioAtTick(),
            _position.token0Balance,
            _position.token1Balance
        );
    }

    /// @notice Compute the amount of collateral/debt to Aave and token0/token1 to Uniswap
    function _computeRebalancePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal view returns (Positions memory position_) {
        if (_assets == 0) return Positions(0, 0, 0, 0);

        // compute ETH/USDC amount ration to add liquidity
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _currentTick.getSqrtRatioAtTick(),
            _lowerTick.getSqrtRatioAtTick(),
            _upperTick.getSqrtRatioAtTick(),
            1e18 //any amount
        );
        uint256 _amount0ValueInToken1 = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_amount0),
            address(token0),
            address(token1)
        );

        if (_hedgeRatio == 0) {
            position_.token1Balance = _assets.mulDiv(_amount1, (_amount0ValueInToken1 + _amount1));
            position_.token0Balance = position_.token1Balance.mulDiv(_amount0, _amount1);
        } else {
            //compute collateral/asset ratio
            uint256 _x = MAGIC_SCALE_1E8.mulDiv(_amount1, _amount0ValueInToken1);
            uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
                _ltv +
                MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
                MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio).mulDiv(_x, MAGIC_SCALE_1E8);

            //Collateral
            position_.collateralAmount1 = _assets.mulDiv(MAGIC_SCALE_1E8, _collateralRatioReciprocal);

            uint256 _borrowUsdc = position_.collateralAmount1.mulDiv(_ltv, MAGIC_SCALE_1E8);
            //borrowing usdc amount to weth
            position_.debtAmount0 = OracleLibrary.getQuoteAtTick(
                _currentTick,
                uint128(_borrowUsdc),
                address(token1),
                address(token0)
            );

            // amount added on Uniswap
            position_.token0Balance = position_.debtAmount0.mulDiv(MAGIC_SCALE_1E8, _hedgeRatio);
            position_.token1Balance = position_.token0Balance.mulDiv(_amount1, _amount0);
        }
    }

    ///@notice Get LTV by current and range prices
    ///@dev called by _computeRebalancePosition. maxLtv * (current price / upper price)
    function _getLtvByRange(int24 _currentTick, int24 _upperTick) internal view returns (uint256 ltv_) {
        uint256 _currentPrice = _quoteEthPriceByTick(_currentTick);
        uint256 _upperPrice = _quoteEthPriceByTick(_upperTick);
        ltv_ = params.maxLtv();
        if (_currentPrice < _upperPrice) {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
        }
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @inheritdoc IOrangeAlphaVault
    function deposit(uint256 _shares, address _receiver, uint256 _maxAssets) external onlyPeriphery returns (uint256) {
        //validation check
        if (_shares == 0 || _maxAssets == 0) revert(Errors.INVALID_AMOUNT);

        // initial deposit
        uint256 _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            if (_maxAssets < params.minDepositAmount()) {
                revert(Errors.INVALID_DEPOSIT_AMOUNT);
            }
            token1.safeTransferFrom(msg.sender, address(this), _maxAssets);
            _mint(_receiver, _maxAssets);
            return _maxAssets;
        }

        Ticks memory _ticks = _getTicksByStorage();

        //compute additional positions by shares
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(_ticks);
        Positions memory _additionalPosition = _computeTargetPositionByShares(
            debtToken0.balanceOf(address(this)),
            aToken1.balanceOf(address(this)),
            _underlyingAssets.token0Balance + _underlyingAssets.accruedFees0, //including pending fees
            _underlyingAssets.token1Balance + _underlyingAssets.accruedFees1, //including pending fees
            _shares,
            _totalSupply
        );

        // Transfer USDC from periphery to Vault
        token1.safeTransferFrom(msg.sender, address(this), _maxAssets);

        // Execute hedge
        aave.safeSupply(address(token1), _additionalPosition.collateralAmount1, address(this), AAVE_REFERRAL_NONE);
        aave.safeBorrow(
            address(token0),
            _additionalPosition.debtAmount0,
            AAVE_VARIABLE_INTEREST,
            AAVE_REFERRAL_NONE,
            address(this)
        );

        // _depositedBalances are deposited balances by sender and will add to pool as liquidity
        Balances memory _depositedBalances = Balances(
            _additionalPosition.debtAmount0,
            _maxAssets - _additionalPosition.collateralAmount1 - _additionalPosition.token1Balance
        );

        // Add liquidity
        _depositLiquidityByShares(_depositedBalances, _shares, _totalSupply, _ticks);

        // Transfer surplus amount to receiver
        if (_depositedBalances.balance0 > 0) {
            token0.safeTransfer(_receiver, _depositedBalances.balance0);
        }
        if (_depositedBalances.balance1 > 0) {
            token1.safeTransfer(_receiver, _depositedBalances.balance1);
        }

        // Mint to receiver
        _mint(_receiver, _shares);

        _emitAction(ActionType.DEPOSIT);
        return _shares;
    }

    ///@notice Add liquidity to pool by share ratio
    ///@dev called by deposit
    function _depositLiquidityByShares(
        Balances memory _depositedBalances,
        uint256 _shares,
        uint256 _totalSupply,
        Ticks memory _ticks
    ) internal {
        (uint128 liquidity, , , , ) = pool.positions(_getPositionID(_ticks.lowerTick, _ticks.upperTick));
        uint128 _additionalLiquidity = SafeCast.toUint128(uint256(liquidity).mulDiv(_shares, _totalSupply));

        if (_additionalLiquidity > 0) {
            (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
            (uint256 _additionalLiquidityAmount0, uint256 _additionalLiquidityAmount1) = LiquidityAmounts
                .getAmountsForLiquidity(
                    _sqrtRatioX96,
                    _ticks.lowerTick.getSqrtRatioAtTick(),
                    _ticks.upperTick.getSqrtRatioAtTick(),
                    _additionalLiquidity
                );

            // 5. swap surplus amount0 or amount1
            _swapSurplusAmountInDeposit(_depositedBalances, _additionalLiquidityAmount0, _additionalLiquidityAmount1);

            // 6. add liquidity
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            (uint256 _token0Balance, uint256 _token1Balance) = pool.mint(
                address(this),
                _ticks.lowerTick,
                _ticks.upperTick,
                _additionalLiquidity,
                ""
            );
            _depositedBalances.balance0 -= _token0Balance;
            _depositedBalances.balance1 -= _token1Balance;
        }
    }

    ///@notice swap surplus amount0 or amount1
    ///@dev called by _depositLiquidityByShares
    function _swapSurplusAmountInDeposit(
        Balances memory _balances,
        uint256 _targetAmount0,
        uint256 _targetAmount1
    ) internal {
        //calculate surplus amount0 and amount1
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
            uint256 _amountOut1 = _swapAmountIn(true, _surplusAmount0);
            _balances.balance0 -= _surplusAmount0;
            _balances.balance1 += _amountOut1;
        } else if (_surplusAmount1 > 0) {
            //swap amount1 to amount0
            uint256 _amountOut0 = _swapAmountIn(false, _surplusAmount1);
            _balances.balance0 += _amountOut0;
            _balances.balance1 -= _surplusAmount1;
        } else {
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
        return _redeem(_shares, _receiver, _minAssets, false);
    }

    /// @inheritdoc IOrangeAlphaVault
    function flashRedeem(
        uint256 _shares,
        address _receiver,
        address,
        uint256 _minAssets
    ) external onlyPeriphery returns (uint256) {
        return _redeem(_shares, _receiver, _minAssets, true);
    }

    function _redeem(
        uint256 _shares,
        address _receiver,
        uint256 _minAssets,
        bool _isFlash
    ) internal returns (uint256 returnAssets_) {
        //validation
        if (_shares == 0) {
            revert(Errors.INVALID_AMOUNT);
        }
        if (balanceOf[_receiver] < _shares) {
            revert(Errors.INVALID_SHARES);
        }

        uint256 _totalSupply = totalSupply;
        Ticks memory _ticks = _getTicksByStorage();

        //burn
        _burn(_receiver, _shares);

        // Remove liquidity by shares and collect all fees
        (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) = _redeemLiqidityByShares(
            _shares,
            _totalSupply,
            _ticks
        );

        //compute redeem positions except liquidity
        //because liquidity is computed by shares
        //so `token0.balanceOf(address(this)) - _burnedLiquidityAmount0` means remaining balance and colleted fee
        Positions memory _redeemPosition = _computeTargetPositionByShares(
            debtToken0.balanceOf(address(this)),
            aToken1.balanceOf(address(this)),
            token0.balanceOf(address(this)) - _burnedLiquidityAmount0,
            token1.balanceOf(address(this)) - _burnedLiquidityAmount1,
            _shares,
            _totalSupply
        );

        // `_redeemedBalances` are currently hold balances in this vault and will transfer to receiver
        Balances memory _redeemableBalances = Balances(
            _redeemPosition.token0Balance + _burnedLiquidityAmount0,
            _redeemPosition.token1Balance + _burnedLiquidityAmount1
        );

        if (!_isFlash) {
            // Swap from USDC to ETH (if necessary)
            if (_redeemableBalances.balance0 < _redeemPosition.debtAmount0) {
                uint256 _amountOutToken0 = _redeemPosition.debtAmount0 - _redeemableBalances.balance0;
                uint256 _amountInToken1 = _swapAmountOut(
                    false, //token1 to token0
                    _amountOutToken0
                );
                _redeemableBalances.balance0 += _amountOutToken0;
                _redeemableBalances.balance1 -= _amountInToken1;
            }

            // Repay ETH
            aave.safeRepay(address(token0), _redeemPosition.debtAmount0, AAVE_VARIABLE_INTEREST, address(this));
            _redeemableBalances.balance0 -= _redeemPosition.debtAmount0;

            // Withdraw USDC as collateral
            aave.safeWithdraw(address(token1), _redeemPosition.collateralAmount1, address(this));
            _redeemableBalances.balance1 += _redeemPosition.collateralAmount1;

            // Swap from ETH to USDC (if necessary)
            if (_redeemableBalances.balance0 > 0) {
                uint256 _amountOut1 = _swapAmountIn(true, _redeemableBalances.balance0);
                _redeemableBalances.balance1 += _amountOut1;
            }

            returnAssets_ = _redeemableBalances.balance1;
        } else {
            // Flashloan to borrow Repay ETH
            if (_redeemPosition.debtAmount0 <= _redeemableBalances.balance0) {
                revert(Errors.NO_NEED_FLASH);
            }
            uint256 _flashBorrowToken0 = _redeemPosition.debtAmount0 - _redeemableBalances.balance0;

            // memorize balance of token1 to be remained in vault
            uint256 _unRedeemableBalance1 = token1.balanceOf(address(this)) - _redeemableBalances.balance1;

            // execute flashloan (repay ETH and withdraw USDC in callback function `executeOperation`)
            aave.flashLoanSimple(
                address(this),
                address(token0),
                _flashBorrowToken0,
                abi.encode(_redeemPosition.debtAmount0, _redeemPosition.collateralAmount1),
                AAVE_REFERRAL_NONE
            );

            returnAssets_ = token1.balanceOf(address(this)) - _unRedeemableBalance1;
        }

        // Transfer USDC from Vault to Receiver
        if (returnAssets_ < _minAssets) {
            revert(Errors.LESS_AMOUNT);
        }
        token1.safeTransfer(_receiver, returnAssets_);

        _emitAction(ActionType.REDEEM);
    }

    ///@notice remove liquidity by share ratio and collect all fees
    ///@dev called by redeem
    function _redeemLiqidityByShares(
        uint256 _shares,
        uint256 _totalSupply,
        Ticks memory _ticks
    ) internal returns (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) {
        (uint128 _liquidity, , , , ) = pool.positions(_getPositionID(_ticks.lowerTick, _ticks.upperTick));
        uint128 _burnLiquidity = SafeCast.toUint128(uint256(_liquidity).mulDiv(_shares, _totalSupply));
        (_burnedLiquidityAmount0, _burnedLiquidityAmount1) = _burnAndCollectFees(
            _ticks.lowerTick,
            _ticks.upperTick,
            _burnLiquidity
        );
    }

    /// @inheritdoc IOrangeAlphaVault
    function stoploss(int24 _inputTick, uint256 _minFinalBalance) external {
        _stoploss(_inputTick, _minFinalBalance, false);
    }

    /// @inheritdoc IOrangeAlphaVault
    function flashStoploss(int24 _inputTick, uint256 _minFinalBalance) external {
        _stoploss(_inputTick, _minFinalBalance, true);
    }

    function _stoploss(int24 _inputTick, uint256 _minFinalBalance, bool _isFlash) internal {
        if (!params.strategists(msg.sender) && params.gelatoExecutor() != msg.sender) {
            revert(Errors.ONLY_STRATEGISTS_OR_GELATO);
        }

        if (totalSupply == 0) return;

        Ticks memory _ticks = _getTicksByStorage();
        _checkTickSlippage(_ticks.currentTick, _inputTick);

        // 1. Remove liquidity
        // 2. Collect fees
        (uint128 liquidity, , , , ) = pool.positions(_getPositionID(_ticks.lowerTick, _ticks.upperTick));
        if (liquidity > 0) {
            _burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick, liquidity);
        }

        uint256 _repayingDebt = debtToken0.balanceOf(address(this));
        uint256 _balanceToken0 = token0.balanceOf(address(this));
        uint256 _withdrawingCollateral = aToken1.balanceOf(address(this));
        if (!_isFlash) {
            // Swap from USDC to ETH (if necessary)
            if (_balanceToken0 < _repayingDebt) {
                _swapAmountOut(
                    false, //token1 to token0
                    _repayingDebt - _balanceToken0
                );
            }

            // Repay ETH
            aave.safeRepay(address(token0), _repayingDebt, AAVE_VARIABLE_INTEREST, address(this));

            // Withdraw USDC as collateral
            aave.safeWithdraw(address(token1), _withdrawingCollateral, address(this));
        } else {
            // Flashloan to borrow Repay ETH
            if (_repayingDebt <= _balanceToken0) {
                revert(Errors.NO_NEED_FLASH);
            }
            uint256 _flashBorrowToken0 = _repayingDebt - _balanceToken0;

            // execute flashloan (repay ETH and withdraw USDC in callback function `executeOperation`)
            aave.flashLoanSimple(
                address(this),
                address(token0),
                _flashBorrowToken0,
                abi.encode(_repayingDebt, _withdrawingCollateral),
                AAVE_REFERRAL_NONE
            );
        }

        // swap remaining all ETH to USDC
        _balanceToken0 = token0.balanceOf(address(this));
        if (_balanceToken0 > 0) {
            _swapAmountIn(true, _balanceToken0);
        }

        // check balance of token1
        if (token1.balanceOf(address(this)) < _minFinalBalance) {
            revert(Errors.LESS_FINAL_BALANCE);
        }

        _emitAction(ActionType.STOPLOSS);
        hasPosition = false;
    }

    /// @inheritdoc IOrangeAlphaVault
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio,
        uint128 _minNewLiquidity
    ) external {
        if (!params.strategists(msg.sender)) {
            revert(Errors.ONLY_STRATEGISTS);
        }
        //validation of tickSpacing
        _validateTicks(_newLowerTick, _newUpperTick);
        _validateTicks(_newStoplossLowerTick, _newStoplossUpperTick);

        Ticks memory _ticks = _getTicksByStorage();
        uint256 _assets = _totalAssets(_ticks);

        // 1. burn and collect fees
        (uint128 _liquidity, , , , ) = pool.positions(_getPositionID(_ticks.lowerTick, _ticks.upperTick));
        _burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick, _liquidity);

        // Update storage of ranges
        _ticks.lowerTick = _newLowerTick; //memory
        _ticks.upperTick = _newUpperTick; //memory
        lowerTick = _newLowerTick;
        upperTick = _newUpperTick;
        stoplossLowerTick = _newStoplossLowerTick;
        stoplossUpperTick = _newStoplossUpperTick;

        if (totalSupply == 0) {
            return;
        }

        // 2. get current position
        Positions memory _currentPosition = Positions(
            debtToken0.balanceOf(address(this)),
            aToken1.balanceOf(address(this)),
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        // 3. compute new position
        uint256 _ltv = _getLtvByRange(_ticks.currentTick, _newStoplossUpperTick);
        Positions memory _targetPosition = _computeRebalancePosition(
            _assets,
            _ticks.currentTick,
            _ticks.lowerTick,
            _ticks.upperTick,
            _ltv,
            _hedgeRatio
        );

        // 4. execute hedge
        _executeHedgeRebalance(_currentPosition, _targetPosition);

        // 5. Add liquidity
        uint128 _targetLiquidity = _addLiquidityInRebalance(
            _ticks.lowerTick,
            _ticks.upperTick,
            _targetPosition.token0Balance, // amount of token0 to be added to Uniswap
            _targetPosition.token1Balance // amount of token1 to be added to Uniswap
        );
        if (_targetLiquidity < _minNewLiquidity) {
            revert(Errors.LESS_LIQUIDITY);
        }

        _emitAction(ActionType.REBALANCE);

        if (_targetLiquidity > 0) {
            hasPosition = true;
        }
    }

    /// @notice execute hedge by changing collateral or debt amount
    /// @dev called by rebalance
    function _executeHedgeRebalance(Positions memory _currentPosition, Positions memory _targetPosition) internal {
        /**memo
         * what if current.collateral == target.collateral. both borrow or repay can come after.
         * We should code special case when one of collateral or debt is equal. But this is one in a million case, so we can wait a few second and execute rebalance again.
         * Maybe, we can revert when one of them is equal.
         */
        if (
            _currentPosition.collateralAmount1 == _targetPosition.collateralAmount1 ||
            _currentPosition.debtAmount0 == _targetPosition.debtAmount0
        ) {
            // if originally collateral is 0, through this function
            if (_currentPosition.collateralAmount1 == 0) return;
            revert(Errors.EQUAL_COLLATERAL_OR_DEBT);
        }
        unchecked {
            if (
                _currentPosition.collateralAmount1 < _targetPosition.collateralAmount1 &&
                _currentPosition.debtAmount0 < _targetPosition.debtAmount0
            ) {
                // case1 supply and borrow
                uint256 _supply = _targetPosition.collateralAmount1 - _currentPosition.collateralAmount1; //uncheckable

                if (_supply > _currentPosition.token1Balance) {
                    // swap (if necessary)
                    _swapAmountOut(
                        true,
                        _supply - _currentPosition.token1Balance //uncheckable
                    );
                }
                aave.safeSupply(address(token1), _supply, address(this), AAVE_REFERRAL_NONE);

                // borrow
                uint256 _borrow = _targetPosition.debtAmount0 - _currentPosition.debtAmount0; //uncheckable
                aave.safeBorrow(address(token0), _borrow, AAVE_VARIABLE_INTEREST, AAVE_REFERRAL_NONE, address(this));
            } else {
                if (_currentPosition.debtAmount0 > _targetPosition.debtAmount0) {
                    // case2 repay
                    uint256 _repay = _currentPosition.debtAmount0 - _targetPosition.debtAmount0; //uncheckable

                    // swap (if necessary)
                    if (_repay > _currentPosition.token0Balance) {
                        _swapAmountOut(
                            false,
                            _repay - _currentPosition.token0Balance //uncheckable
                        );
                    }
                    aave.safeRepay(address(token0), _repay, AAVE_VARIABLE_INTEREST, address(this));

                    if (_currentPosition.collateralAmount1 < _targetPosition.collateralAmount1) {
                        // case2_1 repay and supply
                        uint256 _supply = _targetPosition.collateralAmount1 - _currentPosition.collateralAmount1; //uncheckable
                        aave.safeSupply(address(token1), _supply, address(this), AAVE_REFERRAL_NONE);
                    } else {
                        // case2_2 repay and withdraw
                        uint256 _withdraw = _currentPosition.collateralAmount1 - _targetPosition.collateralAmount1; //uncheckable. //possibly, equal
                        aave.safeWithdraw(address(token1), _withdraw, address(this));
                    }
                } else {
                    // case3 borrow and withdraw
                    uint256 _borrow = _targetPosition.debtAmount0 - _currentPosition.debtAmount0; //uncheckable. //possibly, equal
                    aave.safeBorrow(
                        address(token0),
                        _borrow,
                        AAVE_VARIABLE_INTEREST,
                        AAVE_REFERRAL_NONE,
                        address(this)
                    );
                    // withdraw should be the only option here.
                    uint256 _withdraw = _currentPosition.collateralAmount1 - _targetPosition.collateralAmount1; //should be uncheckable. //possibly, equal
                    aave.safeWithdraw(address(token1), _withdraw, address(this));
                }
            }
        }
    }

    /// @notice Add liquidity to Uniswap after swapping surplus amount if necessary
    /// @dev called by rebalance
    function _addLiquidityInRebalance(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _targetAmount0,
        uint256 _targetAmount1
    ) internal returns (uint128 targetLiquidity_) {
        uint256 _balance0 = token0.balanceOf(address(this));
        uint256 _balance1 = token1.balanceOf(address(this));
        uint160 _sqrtRatioX96;

        //swap surplus amount
        if (_balance0 >= _targetAmount0 && _balance1 >= _targetAmount1) {
            //no need to swap
        } else {
            unchecked {
                if (_balance0 > _targetAmount0) {
                    _swapAmountIn(true, _balance0 - _targetAmount0);
                } else if (_balance1 > _targetAmount1) {
                    _swapAmountIn(false, _balance1 - _targetAmount1);
                }
            }
        }

        (_sqrtRatioX96, , , , , , ) = pool.slot0();
        targetLiquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _sqrtRatioX96,
            _lowerTick.getSqrtRatioAtTick(),
            _upperTick.getSqrtRatioAtTick(),
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        if (targetLiquidity_ > 0) {
            pool.mint(address(this), _lowerTick, _upperTick, targetLiquidity_, "");
        }
    }

    /// @inheritdoc IOrangeAlphaVault
    function emitAction() external {
        _emitAction(ActionType.MANUAL);
    }

    function _emitAction(ActionType _actionType) internal {
        emit Action(_actionType, msg.sender, _totalAssets(_getTicksByStorage()), totalSupply);
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    ///@notice Compute target position by shares
    ///@dev called by deposit and redeem
    function _computeTargetPositionByShares(
        uint256 _debtAmount0,
        uint256 _collateralAmount1,
        uint256 _token0Balance,
        uint256 _token1Balance,
        uint256 _shares,
        uint256 _totalSupply
    ) internal pure returns (Positions memory _position) {
        _position.debtAmount0 = _debtAmount0.mulDiv(_shares, _totalSupply);
        _position.collateralAmount1 = _collateralAmount1.mulDiv(_shares, _totalSupply);
        _position.token0Balance = _token0Balance.mulDiv(_shares, _totalSupply);
        _position.token1Balance = _token1Balance.mulDiv(_shares, _totalSupply);
    }

    ///@notice Compute one of fee amount
    ///@dev similar to Arrakis'
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
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(_ticks.lowerTick);
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(_ticks.upperTick);
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(_ticks.lowerTick);
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(_ticks.upperTick);
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

            uint256 feeGrowthInside = feeGrowthGlobal - feeGrowthBelow - feeGrowthAbove;
            fee = uint256(liquidity).mulDiv(feeGrowthInside - feeGrowthInsideLast, 0x100000000000000000000000000000000);
        }
    }

    ///@notice Get Uniswap's position ID
    function _getPositionID(int24 _lowerTick, int24 _upperTick) internal view returns (bytes32 positionID) {
        return keccak256(abi.encodePacked(address(this), _lowerTick, _upperTick));
    }

    ///@notice Cheking tickSpacing
    function _validateTicks(int24 _lowerTick, int24 _upperTick) internal view {
        int24 _spacing = pool.tickSpacing();
        if (_lowerTick < _upperTick && _lowerTick % _spacing == 0 && _upperTick % _spacing == 0) {
            return;
        }
        revert(Errors.INVALID_TICKS);
    }

    ///@notice Quote eth price by USDC
    function _quoteEthPriceByTick(int24 _tick) internal view returns (uint256) {
        return OracleLibrary.getQuoteAtTick(_tick, 1 ether, address(token0), address(token1));
    }

    ///@notice Get ticks from this storage and Uniswap
    function _getTicksByStorage() internal view returns (Ticks memory) {
        (, int24 _tick, , , , , ) = pool.slot0();
        return Ticks(_tick, lowerTick, upperTick);
    }

    ///@notice Check slippage by tick
    function _checkTickSlippage(int24 _currentTick, int24 _inputTick) internal view {
        if (
            _currentTick > _inputTick + int24(params.tickSlippageBPS()) ||
            _currentTick < _inputTick - int24(params.tickSlippageBPS())
        ) {
            revert(Errors.HIGH_SLIPPAGE);
        }
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */

    ///@notice Remove liquidity from Uniswap and collect fees
    function _burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    ) internal returns (uint256 burn0_, uint256 burn1_) {
        if (_liquidity > 0) {
            (burn0_, burn1_) = pool.burn(_lowerTick, _upperTick, _liquidity);
        }

        pool.collect(address(this), _lowerTick, _upperTick, type(uint128).max, type(uint128).max);
    }

    ///@notice Swap exact amount out
    function _swapAmountOut(bool _zeroForOne, uint256 _amountOut) internal returns (uint256 amountIn_) {
        (address tokenIn, address tokenOut, uint160 _sqrtPriceLimitX96) = _getSlippageOnSwapRouter(_zeroForOne);
        ISwapRouter.ExactOutputSingleParams memory _params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: pool.fee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: _sqrtPriceLimitX96
        });
        amountIn_ = router.exactOutputSingle(_params);
    }

    ///@notice Swap exact amount in
    function _swapAmountIn(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        (address tokenIn, address tokenOut, uint160 _sqrtPriceLimitX96) = _getSlippageOnSwapRouter(_zeroForOne);
        ISwapRouter.ExactInputSingleParams memory _params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: pool.fee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: _sqrtPriceLimitX96
        });
        amountOut_ = router.exactInputSingle(_params);
    }

    ///@notice get slippage and parameters in _swapAmountOut and _swapAmountIn
    /// return parameters (address tokenIn, address tokenOut, uint160 _sqrtPriceLimitX96)
    function _getSlippageOnSwapRouter(bool _zeroForOne) internal view returns (address, address, uint160) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        return
            (_zeroForOne)
                ? (
                    address(token0),
                    address(token1),
                    (_sqrtRatioX96 * (MAGIC_SCALE_1E4 - params.slippageBPS())) / MAGIC_SCALE_1E4
                )
                : (
                    address(token1),
                    address(token0),
                    (_sqrtRatioX96 * (MAGIC_SCALE_1E4 + params.slippageBPS())) / MAGIC_SCALE_1E4
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
            revert(Errors.ONLY_CALLBACK_CALLER);
        }

        if (amount0Owed > 0) {
            // if (amount0Owed > token0.balanceOf(address(this))) {
            //     console2.log("uniswapV3MintCallback amount0 > balance");
            //     console2.log(amount0Owed, token0.balanceOf(address(this)));
            // }
            token0.safeTransfer(msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            // if (amount1Owed > token1.balanceOf(address(this))) {
            //     console2.log("uniswapV3MintCallback amount1 > balance");
            //     console2.log(amount1Owed, token1.balanceOf(address(this)));
            // }
            token1.safeTransfer(msg.sender, amount1Owed);
        }
    }

    /* ========== FLASHLOAN CALLBACK ========== */
    /// @notice _params are _repayAmountToken0, _withdrawAmountToken1
    function executeOperation(
        address _asset,
        uint256 _amount,
        uint256 _premium,
        address,
        bytes calldata _params
    ) external override returns (bool) {
        if (msg.sender != address(aave)) revert(Errors.ONLY_AAVE_POOL);

        (uint256 _repayAmountToken0, uint256 _withdrawAmountToken1) = abi.decode(_params, (uint256, uint256));

        // Repay ETH
        aave.safeRepay(address(token0), _repayAmountToken0, AAVE_VARIABLE_INTEREST, address(this));

        // Withdraw USDC as collateral
        aave.safeWithdraw(address(token1), _withdrawAmountToken1, address(this));

        // swap USDC to ETH to repay flashloan
        uint256 _repayFlashloanAmountToken0 = _amount + _premium;
        _swapAmountOut(
            false, //token1 to token0
            _repayFlashloanAmountToken0
        );

        if (IERC20(_asset).balanceOf(address(this)) < _repayFlashloanAmountToken0)
            revert(Errors.FLASH_LOAN_LACK_OF_BALANCE);
        return true;
    }
}
