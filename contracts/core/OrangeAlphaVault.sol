// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";

//extend
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

//libraries
import {SafeAavePool, IAaveV3Pool} from "../libs/SafeAavePool.sol";
import {Errors} from "../libs/Errors.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TickMath} from "../vendor/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "../vendor/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../vendor/uniswap/OracleLibrary.sol";

import "forge-std/console2.sol";
import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaVault is IOrangeAlphaVault, IUniswapV3MintCallback, IUniswapV3SwapCallback, ERC20 {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using SafeAavePool for IAaveV3Pool;
    // using Ints for int24;

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
    IUniswapV3Pool public immutable pool;
    IERC20 public immutable token0; //weth
    IERC20 public immutable token1; //usdc
    IAaveV3Pool public immutable aave;
    IERC20 immutable debtToken0; //weth
    IERC20 immutable aToken1; //usdc
    IOrangeAlphaParameters public immutable params;

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
        address _aave,
        address _debtToken0,
        address _aToken1,
        address _params
    ) ERC20(_name, _symbol) {
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
    // @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @inheritdoc IOrangeAlphaVault
    /// @dev share is propotion of liquidity. Caluculate hedge position and liquidity position except for hedge position.
    function convertToShares(uint256 _assets) external view returns (uint256 shares_) {
        uint256 _supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _assets : _supply.mulDiv(_assets, _totalAssets(_getTicksByStorage()));
    }

    /// @inheritdoc IOrangeAlphaVault
    function convertToAssets(uint256 _shares) external view returns (uint256) {
        uint256 _supply = totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _shares : _shares.mulDiv(_totalAssets(_getTicksByStorage()), _supply);
    }

    /// @inheritdoc IOrangeAlphaVault
    function totalAssets() external view returns (uint256) {
        if (totalSupply() == 0) return 0;
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

    /**
     * @notice Compute total asset price as USDC
     * @dev Underlying Assets - debt + supply
     * called by _totalAssets
     */
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

    /**
     * @notice Get the amount of underlying assets
     * The assets includes added liquidity, fees and left amount in this vault
     * @dev similar to Arrakis'
     */
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
            _position.debtAmount0,
            _position.collateralAmount1
        );
        // console2.log(liquidity_, "liquidity_");
    }

    /// @notice Compute collateral and borrow amount
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
        // console2.log(_amount0, "_amount0");
        // console2.log(_amount1, "_amount1");
        uint256 _amount0ValueInToken1 = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_amount0),
            address(token0),
            address(token1)
        );
        // console2.log(_amount0ValueInToken1, "_amount0ValueInToken1");

        //compute collateral/asset ratio
        uint256 _x = MAGIC_SCALE_1E8.mulDiv(_amount0ValueInToken1, _amount1);
        // console2.log(_x, "_x");
        uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
            _ltv +
            MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
            MAGIC_SCALE_1E8.mulDiv(_ltv, (_hedgeRatio.mulDiv(_x, MAGIC_SCALE_1E8)));
        // console2.log(_collateralRatioReciprocal, "_collateralRatioReciprocal");

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

        //TODO validate minimum amount
        // if (token1.balanceOf(address(this)) < params.minDepositAmount())
        //     revert(Errors.INVALID_DEPOSIT_AMOUNT);

        // initial deposit
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            token1.safeTransferFrom(msg.sender, address(this), _maxAssets);
            _mint(_receiver, _maxAssets);
            return _maxAssets;
        }

        Ticks memory _ticks = _getTicksByStorage();

        //compute additional positions by shares
        Positions memory _additionalPosition = _computeTargetPositionByShares(
            debtToken0.balanceOf(address(this)),
            aToken1.balanceOf(address(this)),
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this)),
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
            console2.log(_depositedBalances.balance0, "_balances.balance0");
            token0.safeTransfer(_receiver, _depositedBalances.balance0);
        }
        if (_depositedBalances.balance1 > 0) {
            console2.log(_depositedBalances.balance1, "_balances.balance1");
            token1.safeTransfer(_receiver, _depositedBalances.balance1);
        }

        // Mint to receiver
        _mint(_receiver, _shares);

        _emitAction(ActionType.DEPOSIT, _ticks);
        return _shares;
    }

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
            (uint256 _additionalLiquidityAmount0, uint256 _additionalLiquidityAmount1) = LiquidityAmounts
                .getAmountsForLiquidity(
                    _ticks.currentTick.getSqrtRatioAtTick(),
                    _ticks.lowerTick.getSqrtRatioAtTick(),
                    _ticks.upperTick.getSqrtRatioAtTick(),
                    _additionalLiquidity
                );

            // 5. swap surplus amount0 or amount1
            _swapSurplusAmount(_depositedBalances, _additionalLiquidityAmount0, _additionalLiquidityAmount1, _ticks);

            // 6. add liquidity
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
    function _swapSurplusAmount(
        Balances memory _balances,
        uint256 _targetAmount0,
        uint256 _targetAmount1,
        Ticks memory _ticks
    ) internal {
        //calculate surplus amount0 and amount1
        uint256 _surplusAmount0;
        uint256 _surplusAmount1;
        if (_balances.balance0 > _targetAmount0) {
            console2.log(_balances.balance0, "_balances.balance0");
            unchecked {
                _surplusAmount0 = _balances.balance0 - _targetAmount0;
            }
        }
        if (_balances.balance1 > _targetAmount1) {
            console2.log(_balances.balance1, "_balances.balance1");
            unchecked {
                _surplusAmount1 = _balances.balance1 - _targetAmount1;
            }
        }

        if (_surplusAmount0 > 0 && _surplusAmount1 > 0) {
            //no need to swap
            console2.log("surplus no need to swap");
        } else if (_surplusAmount0 > 0) {
            //swap amount0 to amount1
            console2.log("surplus swap amount0 to amount1");
            (int256 _amount0Delta, int256 _amount1Delta) = _swap(
                true,
                _surplusAmount0,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _balances.balance0 = uint256(SafeCast.toInt256(_balances.balance0) - _amount0Delta);
            _balances.balance1 = uint256(SafeCast.toInt256(_balances.balance1) - _amount1Delta);
        } else if (_surplusAmount1 > 0) {
            //swap amount1 to amount0
            console2.log("surplus swap amount1 to amount0");
            (int256 _amount0Delta, int256 _amount1Delta) = _swap(
                false,
                _surplusAmount1,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _balances.balance0 = uint256(SafeCast.toInt256(_balances.balance0) - _amount0Delta);
            _balances.balance1 = uint256(SafeCast.toInt256(_balances.balance1) - _amount1Delta);
        } else {
            console2.log("surplus SURPLUS_ZERO");
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
            revert(Errors.INVALID_AMOUNT);
        }

        uint256 _totalSupply = totalSupply();
        Ticks memory _ticks = _getTicksByStorage();

        //burn
        _burn(_receiver, _shares);

        // 1. Remove liquidity and collect fees
        (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) = _redeemLiqidityByShares(
            _shares,
            _totalSupply,
            _ticks
        );

        //compute redeem positions except liquidity
        Positions memory _redeemPosition = _computeTargetPositionByShares(
            debtToken0.balanceOf(address(this)),
            aToken1.balanceOf(address(this)),
            token0.balanceOf(address(this)) - _burnedLiquidityAmount0,
            token1.balanceOf(address(this)) - _burnedLiquidityAmount1,
            _shares,
            _totalSupply
        );

        //_redeemedBalances are currently hold balances in this vault and will transfer to receiver
        Balances memory _redeemableBalances = Balances(
            _redeemPosition.token0Balance + _burnedLiquidityAmount0,
            _redeemPosition.token1Balance + _burnedLiquidityAmount1
        );

        // 3. Swap from USDC to ETH (if necessary)
        if (_redeemableBalances.balance0 < _redeemPosition.debtAmount0) {
            (int256 amount0Delta, int256 amount1Delta) = _swap(
                false, //token1 to token0
                _redeemableBalances.balance1,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _redeemableBalances.balance0 = uint256(SafeCast.toInt256(_redeemableBalances.balance0) - amount0Delta);
            _redeemableBalances.balance1 = uint256(SafeCast.toInt256(_redeemableBalances.balance1) - amount1Delta);
        }

        // 4. Repay ETH
        aave.safeRepay(address(token0), _redeemPosition.debtAmount0, AAVE_VARIABLE_INTEREST, address(this));
        _redeemableBalances.balance0 -= _redeemPosition.debtAmount0;

        // 5. Withdraw USDC as collateral
        aave.safeWithdraw(address(token1), _redeemPosition.collateralAmount1, address(this));
        _redeemableBalances.balance1 += _redeemPosition.collateralAmount1;

        // 6. Swap from ETH to USDC (if necessary)
        if (_redeemableBalances.balance0 > 0) {
            (, int256 amount1Delta) = _swap(
                true, //token0 to token1
                _redeemableBalances.balance0,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _redeemableBalances.balance1 = uint256(SafeCast.toInt256(_redeemableBalances.balance1) - amount1Delta);
        }

        // 7. Transfer USDC from Vault to Pool
        if (_minAssets > _redeemableBalances.balance1) {
            revert(Errors.LESS_AMOUNT);
        }
        token1.safeTransfer(_receiver, _redeemableBalances.balance1);

        _emitAction(ActionType.REDEEM, _ticks);
        return _redeemableBalances.balance1;
    }

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
    function emitAction() external {
        _emitAction(ActionType.MANUAL, _getTicksByStorage());
    }

    function _emitAction(ActionType _actionType, Ticks memory _ticks) internal {
        emit Action(_actionType, msg.sender, _totalAssets(_ticks), totalSupply());
    }

    /// @inheritdoc IOrangeAlphaVault
    function stoploss(int24 _inputTick) external {
        if (!params.strategists(msg.sender) && params.gelato() != msg.sender) {
            revert(Errors.ONLY_STRATEGISTS_OR_GELATO);
        }

        if (totalSupply() == 0) return;

        Ticks memory _ticks = _getTicksByStorage();
        _checkTickSlippage(_ticks.currentTick, _inputTick);

        // 1. Remove liquidity
        // 2. Collect fees
        (uint128 liquidity, , , , ) = pool.positions(_getPositionID(_ticks.lowerTick, _ticks.upperTick));
        if (liquidity > 0) {
            _burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick, liquidity);
        }

        // 3. Swap from USDC to ETH (if necessary)
        uint256 _repayingDebt = debtToken0.balanceOf(address(this));
        if (token0.balanceOf(address(this)) < _repayingDebt) {
            _swap(
                false, //token1 to token0
                token1.balanceOf(address(this)),
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
        }

        // 4. Repay ETH
        aave.safeRepay(address(token0), _repayingDebt, AAVE_VARIABLE_INTEREST, address(this));

        // 5. Withdraw USDC as collateral
        uint256 _withdrawingCollateral = aToken1.balanceOf(address(this));
        aave.safeWithdraw(address(token1), _withdrawingCollateral, address(this));

        // swap ETH to USDC
        uint256 _balanceToken0 = token0.balanceOf(address(this));
        if (_balanceToken0 > 0) {
            _swap(
                true, //token0 to token1
                _balanceToken0,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
        }

        _emitAction(ActionType.STOPLOSS, _ticks);
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

        // 2. get current position
        Positions memory _currentPosition = Positions(
            debtToken0.balanceOf(address(this)),
            aToken1.balanceOf(address(this)),
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        // Update storage of ranges
        _ticks.lowerTick = _newLowerTick; //memory
        _ticks.upperTick = _newUpperTick; //memory
        lowerTick = _newLowerTick;
        upperTick = _newUpperTick;
        stoplossLowerTick = _newStoplossLowerTick;
        stoplossUpperTick = _newStoplossUpperTick;

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
        _executeHedgeRebalance(_currentPosition, _targetPosition, _ticks);

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

        _emitAction(ActionType.REBALANCE, _ticks);

        if (_targetLiquidity > 0) {
            hasPosition = true;
        }
    }

    /// @notice execute hedge by changing collateral or debt amount
    /// @dev colled by rebalance
    function _executeHedgeRebalance(
        Positions memory _currentPosition,
        Positions memory _targetPosition,
        Ticks memory _ticks
    ) internal {
        /**memo
         * what if current.collateral == target.collateral. both borrow or repay can come after.
         * We should code special case when one of collateral or debt is equal. But this is one in a million case, so we can wait a few second and execute rebalance again.
         * Maybe, we can revert when one of them is equal.
         */
        if (
            _currentPosition.collateralAmount1 == _targetPosition.collateralAmount1 ||
            _currentPosition.debtAmount0 == _targetPosition.debtAmount0
        ) {
            revert(Errors.EQUAL_COLLATERAL_OR_DEBT);
        }
        unchecked {
            if (
                //1. supply and borrow
                _currentPosition.collateralAmount1 < _targetPosition.collateralAmount1 &&
                _currentPosition.debtAmount0 < _targetPosition.debtAmount0
            ) {
                console2.log("case1 supply and borrow");
                // case1 supply and borrow
                uint256 _supply = _targetPosition.collateralAmount1 - _currentPosition.collateralAmount1; //uncheckable

                if (_supply > _currentPosition.token1Balance) {
                    // swap (if necessary)
                    _swapAmountOut(
                        true,
                        uint128(_supply - _currentPosition.token1Balance), //uncheckable
                        _ticks.currentTick
                    );
                }
                aave.safeSupply(address(token1), _supply, address(this), AAVE_REFERRAL_NONE);

                // borrow
                uint256 _borrow = _targetPosition.debtAmount0 - _currentPosition.debtAmount0; //uncheckable
                aave.safeBorrow(address(token0), _borrow, AAVE_VARIABLE_INTEREST, AAVE_REFERRAL_NONE, address(this));
            } else {
                if (_currentPosition.debtAmount0 > _targetPosition.debtAmount0) {
                    console2.log("case2 repay");
                    // case2 repay
                    uint256 _repay = _currentPosition.debtAmount0 - _targetPosition.debtAmount0; //uncheckable

                    // swap (if necessary)
                    if (_repay > _currentPosition.token0Balance) {
                        _swapAmountOut(
                            false,
                            uint128(_repay - _currentPosition.token0Balance), //uncheckable
                            _ticks.currentTick
                        );
                    }
                    aave.safeRepay(address(token0), _repay, AAVE_VARIABLE_INTEREST, address(this));

                    if (_currentPosition.collateralAmount1 < _targetPosition.collateralAmount1) {
                        console2.log("case2_1 repay and supply");
                        // case2_1 repay and supply
                        uint256 _supply = _targetPosition.collateralAmount1 - _currentPosition.collateralAmount1; //uncheckable
                        aave.safeSupply(address(token1), _supply, address(this), AAVE_REFERRAL_NONE);
                    } else {
                        console2.log("case2_2 repay and withdraw");
                        // case2_2 repay and withdraw
                        uint256 _withdraw = _currentPosition.collateralAmount1 - _targetPosition.collateralAmount1; //uncheckable. //possibly, equal
                        aave.safeWithdraw(address(token1), _withdraw, address(this));
                    }
                } else {
                    console2.log("case3 borrow and withdraw");
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

    /// @notice if current balance > totalSwapAmount, swap total amount.
    /// Otherwise, swap current balance( and will swap afterward)
    /// @dev called by _executeHedgeRebalance
    function _swapAmountOut(bool _zeroForOne, uint128 _minAmountOut, int24 _tick) internal {
        uint256 _amountIn;
        if (_zeroForOne) {
            _amountIn = OracleLibrary.getQuoteAtTick(_tick, _minAmountOut, address(token1), address(token0));
            _amountIn = _amountIn.mulDiv(MAGIC_SCALE_1E4 + params.slippageBPS(), MAGIC_SCALE_1E4);
            if (_amountIn > token0.balanceOf(address(this))) {
                console2.log(_amountIn, token0.balanceOf(address(this)));
                revert(Errors.LACK_OF_TOKEN0);
            }
        } else {
            _amountIn = OracleLibrary.getQuoteAtTick(_tick, _minAmountOut, address(token0), address(token1));
            _amountIn = _amountIn.mulDiv(MAGIC_SCALE_1E4 + params.slippageBPS(), MAGIC_SCALE_1E4);
            if (_amountIn > token1.balanceOf(address(this))) {
                console2.log(_amountIn, token1.balanceOf(address(this)));
                revert(Errors.LACK_OF_TOKEN1);
            }
        }
        _swap(_zeroForOne, _amountIn, _tick.getSqrtRatioAtTick());
    }

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
                    console2.log("_addLiquidityInRebalance case1");
                    (_sqrtRatioX96, , , , , , ) = pool.slot0();
                    _swap(
                        true,
                        uint128(_balance0 - _targetAmount0), //uncheckable
                        _sqrtRatioX96
                    );
                } else if (_balance1 > _targetAmount1) {
                    console2.log("_addLiquidityInRebalance case2");
                    (_sqrtRatioX96, , , , , , ) = pool.slot0();
                    _swap(
                        false,
                        uint128(_balance1 - _targetAmount1), //uncheckable
                        _sqrtRatioX96
                    );
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

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
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

    function _checkTickSlippage(int24 _currentTick, int24 _inputTick) internal view {
        //check slippage by tick
        if (
            _currentTick > _inputTick + int24(params.tickSlippageBPS()) ||
            _currentTick < _inputTick - int24(params.tickSlippageBPS())
        ) {
            revert(Errors.HIGH_SLIPPAGE);
        }
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
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

    function _swap(
        bool _zeroForOne,
        uint256 _swapAmount,
        uint256 _currentSqrtRatioX96
    ) internal returns (int256 _amount0Delta, int256 _amount1Delta) {
        uint160 _swapThresholdPrice;
        if (_zeroForOne) {
            _swapThresholdPrice = uint160(
                _currentSqrtRatioX96.mulDiv(MAGIC_SCALE_1E4 - params.slippageBPS(), MAGIC_SCALE_1E4)
            );
        } else {
            _swapThresholdPrice = uint160(
                _currentSqrtRatioX96.mulDiv(MAGIC_SCALE_1E4 + params.slippageBPS(), MAGIC_SCALE_1E4)
            );
        }

        return pool.swap(address(this), _zeroForOne, SafeCast.toInt256(_swapAmount), _swapThresholdPrice, "");
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
            // console2.log("uniswapV3MintCallback amount0");
            if (amount0Owed > token0.balanceOf(address(this))) {
                console2.log("uniswapV3MintCallback amount0 > balance");
                console2.log(amount0Owed, token0.balanceOf(address(this)));
            }
            token0.safeTransfer(msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            // console2.log("uniswapV3MintCallback amount1");
            if (amount1Owed > token1.balanceOf(address(this))) {
                console2.log("uniswapV3MintCallback amount1 > balance");
                console2.log(amount1Owed, token1.balanceOf(address(this)));
            }
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
            revert(Errors.ONLY_CALLBACK_CALLER);
        }

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
