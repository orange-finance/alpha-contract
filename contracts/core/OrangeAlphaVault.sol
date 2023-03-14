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

contract OrangeAlphaVault is
    IOrangeAlphaVault,
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback,
    ERC20
{
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using SafeAavePool for IAaveV3Pool;
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
    IERC20 public token0; //weth
    IERC20 public token1; //usdc
    IAaveV3Pool public aave;
    IERC20 debtToken0; //weth
    IERC20 aToken1; //usdc
    uint8 _decimal;
    IOrangeAlphaParameters public params;

    /* ========== MODIFIER ========== */
    modifier onlyPeriphery() {
        if (msg.sender != params.periphery()) revert(Errors.ONLY_PERIPHERY);
        _;
    }

    modifier onlyStrategists() {
        if (!params.strategists(msg.sender)) {
            revert(Errors.ONLY_STRATEGISTS);
        }
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
    function convertToShares(
        uint256 _assets
    ) external view returns (uint256 shares_) {
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
        if (totalSupply() == 0) return 0;
        return _totalAssets(_getTicksByStorage());
    }

    ///@notice internal function of totalAssets
    function _totalAssets(
        Ticks memory _ticks
    ) internal view returns (uint256 totalAssets_) {
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(
            _ticks
        );
        uint256 amount0Debt = debtToken0.balanceOf(address(this));
        uint256 amount1Supply = aToken1.balanceOf(address(this));

        uint256 amount0Current = _underlyingAssets.amount0Current +
            _underlyingAssets.accruedFees0 +
            _underlyingAssets.amount0Balance;
        uint256 amount1Current = _underlyingAssets.amount1Current +
            _underlyingAssets.accruedFees1 +
            _underlyingAssets.amount1Balance;
        return
            _alignTotalAsset(
                _ticks,
                amount0Current,
                amount1Current,
                amount0Debt,
                amount1Supply
            );
    }

    /**
     * @notice Compute total asset price as USDC
     * @dev Underlying Assets - debt + supply
     * called by _totalAssets
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

    /// @inheritdoc IOrangeAlphaVault
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
        uint256 _ltv = _getLtvByRange(
            _ticks.currentTick,
            _newStoplossUpperTick
        );
        Position memory _position = _computePosition(
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
            _position.supplyAmount1
        );
        // console2.log(liquidity_, "liquidity_");
    }

    /// @notice Compute collateral and borrow amount
    function _computePosition(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _ltv,
        uint256 _hedgeRatio
    ) internal view returns (Position memory position_) {
        if (_assets == 0) return Position(0, 0, 0, 0);

        // compute ETH/USDC amount ration to add liquidity
        (uint256 _amount0, uint256 _amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                _currentTick.getSqrtRatioAtTick(),
                _lowerTick.getSqrtRatioAtTick(),
                _upperTick.getSqrtRatioAtTick(),
                1e18 //any amount
            );
        // console2.log(_amount0, "_amount0");
        // console2.log(_amount1, "_amount1");
        uint256 _amount0Usdc = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_amount0),
            address(token0),
            address(token1)
        );
        // console2.log(_amount0Usdc, "_amount0Usdc");

        //compute collateral/asset ratio
        uint256 _x = MAGIC_SCALE_1E8.mulDiv(_amount0Usdc, _amount1);
        // console2.log(_x, "_x");
        uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
            _ltv +
            MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
            MAGIC_SCALE_1E8.mulDiv(
                _ltv,
                (_hedgeRatio.mulDiv(_x, MAGIC_SCALE_1E8))
            );
        // console2.log(_collateralRatioReciprocal, "_collateralRatioReciprocal");

        //Collateral
        position_.supplyAmount1 = _assets.mulDiv(
            MAGIC_SCALE_1E8,
            _collateralRatioReciprocal
        );

        uint256 _borrowUsdc = position_.supplyAmount1.mulDiv(
            _ltv,
            MAGIC_SCALE_1E8
        );
        //borrowing usdc amount to weth
        position_.debtAmount0 = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_borrowUsdc),
            address(token1),
            address(token0)
        );

        // amount added on Uniswap
        position_.addedAmount0 = position_.debtAmount0.mulDiv(
            MAGIC_SCALE_1E8,
            _hedgeRatio
        );
        position_.addedAmount1 = position_.addedAmount0.mulDiv(
            _amount1,
            _amount0
        );
    }

    ///@notice Get LTV by current and range prices
    ///@dev called by _computePosition. maxLtv * (current price / upper price)
    function _getLtvByRange(
        int24 _currentTick,
        int24 _upperTick
    ) internal view returns (uint256 ltv_) {
        uint256 _currentPrice = _quoteEthPriceByTick(_currentTick);
        uint256 _upperPrice = _quoteEthPriceByTick(_upperTick);
        ltv_ = params.maxLtv();
        if (_currentPrice < _upperPrice) {
            ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
        }
    }

    /// @inheritdoc IOrangeAlphaVault
    function canStoploss(
        int24 _targetTick,
        int24 _lowerTick,
        int24 _upperTick
    ) external view returns (bool) {
        return _canStoploss(_targetTick, _lowerTick, _upperTick);
    }

    ///@notice Can stoploss when not stopplossed and out of range
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

    /* ========== EXTERNAL FUNCTIONS ========== */
    /// @inheritdoc IOrangeAlphaVault
    function deposit(
        uint256 _shares,
        address _receiver,
        uint256 _maxAssets
    ) external onlyPeriphery returns (uint256) {
        //validation check
        if (_shares == 0 || _maxAssets == 0) revert(Errors.INVALID_AMOUNT);

        //get vault balance
        uint256 _beforeBalance1 = token1.balanceOf(address(this));

        // 1. Transfer USDC from periphery to Vault
        token1.safeTransferFrom(msg.sender, address(this), _maxAssets);

        //validate minimum amount
        if (token1.balanceOf(address(this)) < params.minDepositAmount())
            revert(Errors.INVALID_DEPOSIT_AMOUNT);

        // initial deposit
        if (totalSupply() == 0) {
            _mint(_receiver, _maxAssets);
            return _maxAssets;
        }

        // 2. compute store token1
        uint256 _storeBalance1 = _beforeBalance1.mulDiv(_shares, totalSupply());

        // 3. compute hedge amount and liquidity by shares
        Ticks memory _ticks = _getTicksByStorage();
        (
            uint256 _targetDebtAmount0,
            uint256 _targetCollateralAmount1,
            uint128 _targetLiquidity
        ) = _computeHedgeAndLiquidityByShares(_shares, _ticks);

        // 4. execute hedge
        aave.safeSupply(
            address(token1),
            _targetCollateralAmount1,
            address(this),
            0
        );
        aave.safeBorrow(
            address(token0),
            _targetDebtAmount0,
            2,
            0,
            address(this)
        );

        // 5. swap surplus amount0 or amount1
        Balances memory _balances = Balances(
            _targetDebtAmount0,
            _maxAssets - _targetCollateralAmount1 - _storeBalance1
        );
        _swapSurplusAmount(_balances, _targetLiquidity, _ticks);

        // 6. add liquidity
        if (_targetLiquidity > 0) {
            (uint256 _addedAmount0, uint256 _addedAmount1) = pool.mint(
                address(this),
                _ticks.lowerTick,
                _ticks.upperTick,
                _targetLiquidity,
                ""
            );
            _balances.balance0 -= _addedAmount0;
            _balances.balance1 -= _addedAmount1;
        }

        //transfer surplus amount to receiver
        if (_balances.balance0 > 0) {
            console2.log(_balances.balance0, "_balances.balance0");
            token0.safeTransfer(_receiver, _balances.balance0);
        }
        if (_balances.balance1 > 0) {
            console2.log(_balances.balance1, "_balances.balance1");
            token1.safeTransfer(_receiver, _balances.balance1);
        }

        //mint to receiver
        _mint(_receiver, _shares);

        _emitAction(1, _ticks);
        return _shares;
    }

    ///@dev called by deposit
    function _computeHedgeAndLiquidityByShares(
        uint256 _shares,
        Ticks memory _ticks
    )
        internal
        view
        returns (
            uint256 _targetDebtAmount0,
            uint256 _targetCollateralAmount1,
            uint128 _targetLiquidity
        )
    {
        // totalSupply() must not be zero because of validation check in deposit function
        uint256 _totalSupply = totalSupply();

        // compute hedge amount by shares
        _targetDebtAmount0 = debtToken0.balanceOf(address(this)).mulDiv(
            _shares,
            _totalSupply
        );
        _targetCollateralAmount1 = aToken1.balanceOf(address(this)).mulDiv(
            _shares,
            _totalSupply
        );

        // compute liquidity amount by shares
        (uint128 liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        _targetLiquidity = uint128(
            uint256(liquidity).mulDiv(_shares, _totalSupply)
        );
    }

    ///@notice swap surplus amount0 or amount1
    ///@dev called by _computeHedgeAndLiquidityByShares
    function _swapSurplusAmount(
        Balances memory _balances,
        uint128 _targetLiquidity,
        Ticks memory _ticks
    ) internal {
        console2.log(_balances.balance0, "_balances.balance0");
        console2.log(_balances.balance1, "_balances.balance1");

        //calulate target amount0 and amount1 by liquidity
        (uint256 _targetAmount0, uint256 _targetAmount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                _ticks.currentTick.getSqrtRatioAtTick(),
                _ticks.lowerTick.getSqrtRatioAtTick(),
                _ticks.upperTick.getSqrtRatioAtTick(),
                _targetLiquidity
            );
        console2.log(_targetAmount0, "_targetAmount0");
        console2.log(_targetAmount1, "_targetAmount1");

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
            _balances.balance0 = uint256(
                SafeCast.toInt256(_balances.balance0) - _amount0Delta
            );
            _balances.balance1 = uint256(
                SafeCast.toInt256(_balances.balance1) - _amount1Delta
            );
        } else if (_surplusAmount1 > 0) {
            //swap amount1 to amount0
            console2.log("surplus swap amount1 to amount0");
            (int256 _amount0Delta, int256 _amount1Delta) = _swap(
                false,
                _surplusAmount1,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _balances.balance0 = uint256(
                SafeCast.toInt256(_balances.balance0) - _amount0Delta
            );
            _balances.balance1 = uint256(
                SafeCast.toInt256(_balances.balance1) - _amount1Delta
            );
        } else if (_surplusAmount0 == 0 && _surplusAmount1 == 0) {
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

        // 1. Remove liquidity
        // 2. Collect fees
        (uint256 _assets0, uint256 _assets1) = _burnShare(
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
            (int256 amount0Delta, int256 amount1Delta) = _swap(
                false, //token1 to token0
                _assets1,
                _ticks.currentTick.getSqrtRatioAtTick()
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
            (, int256 amount1Delta) = _swap(
                true, //token0 to token1
                _assets0,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
            _assets1 = uint256(SafeCast.toInt256(_assets1) - amount1Delta);
        }

        // 7. Transfer USDC from Vault to Pool
        if (_minAssets > _assets1) {
            revert(Errors.LESS_AMOUNT);
        }
        token1.safeTransfer(_receiver, _assets1);

        _emitAction(2, _ticks);
        return _assets1;
    }

    ///@notice Burn liquidity per share and compute underlying amount per share
    ///@dev called by redeem function
    function _burnShare(
        uint256 _shares,
        uint256 _totalSupply,
        Ticks memory _ticks
    ) internal returns (uint256 burnAndFees0_, uint256 burnAndFees1_) {
        (uint128 _liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        uint128 _liquidityBurned = SafeCast.toUint128(
            FullMath.mulDiv(_shares, _liquidity, _totalSupply)
        );

        (
            uint256 _burn0,
            uint256 _burn1,
            uint256 _fee0,
            uint256 _fee1
        ) = _burnAndCollectFees(
                _ticks.lowerTick,
                _ticks.upperTick,
                _liquidityBurned
            );
        //fee and remaining
        _fee0 = FullMath.mulDiv(
            _shares,
            _fee0 + token0.balanceOf(address(this)),
            _totalSupply
        );
        _fee1 = FullMath.mulDiv(
            _shares,
            _fee1 + token1.balanceOf(address(this)),
            _totalSupply
        );
        burnAndFees0_ = _burn0 + _fee0;
        burnAndFees1_ = _burn1 + _fee1;
    }

    /// @inheritdoc IOrangeAlphaVault
    function emitAction() external {
        _emitAction(0, _getTicksByStorage());
    }

    function _emitAction(uint8 _actionType, Ticks memory _ticks) internal {
        emit Action(
            _actionType,
            msg.sender,
            _totalAssets(_ticks),
            totalSupply()
        );
    }

    /// @inheritdoc IOrangeAlphaVault
    function stoploss(int24 _inputTick) external {
        if (params.dedicatedMsgSender() != msg.sender) {
            revert(Errors.ONLY_DEDICATED_MSG_SENDER);
        }
        Ticks memory _ticks = _getTicksByStorage();
        if (
            !_canStoploss(
                _ticks.currentTick,
                stoplossLowerTick,
                stoplossUpperTick
            )
        ) {
            revert(Errors.CANNOT_STOPLOSS);
        }
        _checkTickSlippage(_ticks.currentTick, _inputTick);

        stoplossed = true;
        _removeAllPosition(_ticks);
        _emitAction(4, _ticks);
    }

    /* ========== ADMINS FUNCTIONS ========== */
    /// @inheritdoc IOrangeAlphaVault
    function removeAllPosition(int24 _inputTick) external onlyStrategists {
        Ticks memory _ticks = _getTicksByStorage();
        _checkTickSlippage(_ticks.currentTick, _inputTick);

        _removeAllPosition(_ticks);
        _emitAction(5, _ticks);
    }

    ///@notice remove all positions and swap to USDC
    function _removeAllPosition(Ticks memory _ticks) internal {
        if (totalSupply() == 0) return;

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
            _swap(
                false, //token1 to token0
                token1.balanceOf(address(this)),
                _ticks.currentTick.getSqrtRatioAtTick()
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
            _swap(
                true, //token0 to token1
                _balanceToken0,
                _ticks.currentTick.getSqrtRatioAtTick()
            );
            (, _ticks.currentTick, , , , , ) = pool.slot0(); //retrieve tick again
        }
    }

    /// @inheritdoc IOrangeAlphaVault
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint256 _hedgeRatio,
        uint128 _minNewLiquidity
    ) external onlyStrategists {
        //validation of tickSpacing
        _validateTicks(_newLowerTick, _newUpperTick);
        _validateTicks(_newStoplossLowerTick, _newStoplossUpperTick);

        Ticks memory _ticks = _getTicksByStorage();
        uint256 _assets = _totalAssets(_ticks);

        // 1. burn and collect fees
        (uint128 _liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        _burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick, _liquidity);

        // 2. get current position
        Position memory _oldPosition = Position(
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
        uint256 _ltv = _getLtvByRange(
            _ticks.currentTick,
            _newStoplossUpperTick
        );
        Position memory _newPosition = _computePosition(
            _assets,
            _ticks.currentTick,
            _newLowerTick,
            _newUpperTick,
            _ltv,
            _hedgeRatio
        );
        console2.log(_newPosition.debtAmount0, "debtAmount0");
        console2.log(_newPosition.supplyAmount1, "supplyAmount1");
        console2.log(_newPosition.addedAmount0, "addedAmount0");
        console2.log(_newPosition.addedAmount1, "addedAmount1");

        // 4. execute hedge
        _executeHedgeRebalance(_oldPosition, _newPosition, _ticks);

        // 5. Add liquidity
        uint128 _targetLiquidity = _addLiquidityInRebalance(
            _ticks.lowerTick,
            _ticks.upperTick,
            _newPosition.addedAmount0,
            _newPosition.addedAmount1
        );
        if (_targetLiquidity < _minNewLiquidity) {
            revert(Errors.LESS_LIQUIDITY);
        }

        _emitAction(3, _ticks);

        //reset stoplossed
        stoplossed = false;
    }

    /// @notice execute hedge by changing collateral or debt amount
    /// @dev colled by rebalance
    function _executeHedgeRebalance(
        Position memory _oldPosition,
        Position memory _newPosition,
        Ticks memory _ticks
    ) internal {
        console2.log("_executeHedgeRebalance 0");
        if (
            //1. supply and borrow
            _oldPosition.debtAmount0 < _newPosition.debtAmount0 &&
            _oldPosition.supplyAmount1 < _newPosition.supplyAmount1
        ) {
            console2.log("case1 supply and borrow");
            // supply
            uint256 _supply = _newPosition.supplyAmount1 -
                _oldPosition.supplyAmount1;

            if (_supply > _oldPosition.addedAmount1) {
                console2.log(_supply, "_supply");
                console2.log(_oldPosition.addedAmount1, "addedAmount1");
                console2.log(token1.balanceOf(address(this)), "token1balance");

                // swap (if necessary)
                console2.log("case1 1");
                _swapAmountOut(
                    true,
                    uint128(_supply - _oldPosition.addedAmount1),
                    _ticks.currentTick
                );
            }
            console2.log("case1 2");
            aave.safeSupply(address(token1), _supply, address(this), 0);

            // borrow
            uint256 _borrow = _newPosition.debtAmount0 -
                _oldPosition.debtAmount0;
            aave.safeBorrow(address(token0), _borrow, 2, 0, address(this));
        } else {
            if (_oldPosition.debtAmount0 > _newPosition.debtAmount0) {
                console2.log("case2 repay");
                // repay
                uint256 _repay = _oldPosition.debtAmount0 -
                    _newPosition.debtAmount0;
                // console2.log(_repay, "_repay");
                // console2.log(token0.balanceOf(address(this)), "token0balance");
                // console2.log(token1.balanceOf(address(this)), "token1balance");

                // swap (if necessary)
                if (_repay > _oldPosition.addedAmount0) {
                    // swap (if necessary)
                    _swapAmountOut(
                        false,
                        uint128(_repay - _oldPosition.addedAmount0),
                        _ticks.currentTick
                    );
                }
                console2.log("case2 1");
                aave.safeRepay(address(token0), _repay, 2, address(this));
                console2.log("case2 2");
            } else {
                console2.log("case3 borrow");
                // borrow
                uint256 _borrow = _newPosition.debtAmount0 -
                    _oldPosition.debtAmount0;
                aave.safeBorrow(address(token0), _borrow, 2, 0, address(this));
            }

            if (_oldPosition.supplyAmount1 < _newPosition.supplyAmount1) {
                console2.log("case4 supply");
                // supply
                uint256 _supply = _newPosition.supplyAmount1 -
                    _oldPosition.supplyAmount1;
                aave.safeSupply(address(token1), _supply, address(this), 0);
            } else {
                console2.log("case5 withdraw");
                // withdraw
                uint256 _withdraw = _oldPosition.supplyAmount1 -
                    _newPosition.supplyAmount1;
                aave.safeWithdraw(address(token1), _withdraw, address(this));
            }
        }
    }

    /// @notice if current balance > totalSwapAmount, swap total amount.
    /// Otherwise, swap current balance( and will swap afterward)
    /// @dev called by _executeHedgeRebalance
    function _swapAmountOut(
        bool _zeroForOne,
        uint128 _minAmountOut,
        int24 _tick
    ) internal {
        uint256 _amountIn;
        if (_zeroForOne) {
            _amountIn = OracleLibrary.getQuoteAtTick(
                _tick,
                _minAmountOut,
                address(token1),
                address(token0)
            );
            _amountIn = _amountIn.mulDiv(
                MAGIC_SCALE_1E4 + params.slippageBPS(),
                MAGIC_SCALE_1E4
            );
            if (_amountIn > token0.balanceOf(address(this))) {
                console2.log(_amountIn, token0.balanceOf(address(this)));
                revert(Errors.LACK_OF_TOKEN0);
            }
        } else {
            _amountIn = OracleLibrary.getQuoteAtTick(
                _tick,
                _minAmountOut,
                address(token0),
                address(token1)
            );
            _amountIn = _amountIn.mulDiv(
                MAGIC_SCALE_1E4 + params.slippageBPS(),
                MAGIC_SCALE_1E4
            );
            if (_amountIn > token1.balanceOf(address(this))) {
                console2.log(_amountIn, token1.balanceOf(address(this)));
                revert(Errors.LACK_OF_TOKEN1);
            }
        }
        _swap(_zeroForOne, _amountIn, _tick.getSqrtRatioAtTick());
    }

    function _addLiquidityInRebalance(
        int24 _lowerTick,
        int24 _upperTick,
        uint256 _targetAmount0,
        uint256 _targetAmount1
    ) internal returns (uint128 targetLiquidity_) {
        uint256 _balance0 = token0.balanceOf(address(this));
        uint256 _balance1 = token1.balanceOf(address(this));
        console2.log("balance0", _balance0);
        console2.log("balance1", _balance1);
        console2.log("targetAmount0", _targetAmount0);
        console2.log("targetAmount1", _targetAmount1);
        uint160 _sqrtRatioX96;

        //swap surplus amount
        if (_balance0 >= _targetAmount0 && _balance1 >= _targetAmount1) {
            //no need to swap
        } else {
            if (_balance0 > _targetAmount0) {
                (_sqrtRatioX96, , , , , , ) = pool.slot0();
                _swap(true, uint128(_balance0 - _targetAmount0), _sqrtRatioX96);
            } else if (_balance1 > _targetAmount1) {
                (_sqrtRatioX96, , , , , , ) = pool.slot0();
                _swap(
                    false,
                    uint128(_balance1 - _targetAmount1),
                    _sqrtRatioX96
                );
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
            pool.mint(
                address(this),
                _lowerTick,
                _upperTick,
                targetLiquidity_,
                ""
            );
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

    ///@notice Get Uniswap's position ID
    function _getPositionID(
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (bytes32 positionID) {
        return
            keccak256(abi.encodePacked(address(this), _lowerTick, _upperTick));
    }

    ///@notice Cheking tickSpacing
    function _validateTicks(int24 _lowerTick, int24 _upperTick) internal view {
        int24 _spacing = pool.tickSpacing();
        if (
            _lowerTick < _upperTick &&
            _lowerTick % _spacing == 0 &&
            _upperTick % _spacing == 0
        ) {
            return;
        }
        revert(Errors.INVALID_TICKS);
    }

    ///@notice Quote eth price by USDC
    function _quoteEthPriceByTick(int24 _tick) internal view returns (uint256) {
        return
            OracleLibrary.getQuoteAtTick(
                _tick,
                1 ether,
                address(token0),
                address(token1)
            );
    }

    ///@notice Get ticks from this storage and Uniswap
    function _getTicksByStorage() internal view returns (Ticks memory) {
        (, int24 _tick, , , , , ) = pool.slot0();
        return Ticks(_tick, lowerTick, upperTick);
    }

    ///@notice Get ticks from this storage and Uniswap
    function _swap(
        bool _zeroForOne,
        uint256 _swapAmount,
        uint256 _currentSqrtRatioX96
    ) internal returns (int256 _amount0Delta, int256 _amount1Delta) {
        uint160 _swapThresholdPrice;
        // prettier-ignore
        if (_zeroForOne) { 
            _swapThresholdPrice= uint160(
                FullMath.mulDiv(
                    _currentSqrtRatioX96,
                    params.slippageBPS(),
                    MAGIC_SCALE_1E4
                )
            );
        } else {
            _swapThresholdPrice= uint160(
                FullMath.mulDiv(
                    _currentSqrtRatioX96,
                    MAGIC_SCALE_1E4 + params.slippageBPS(),
                    MAGIC_SCALE_1E4
                )
            );
        }

        return
            pool.swap(
                address(this),
                _zeroForOne,
                SafeCast.toInt256(_swapAmount),
                _swapThresholdPrice,
                ""
            );
    }

    function _checkTickSlippage(
        int24 _currentTick,
        int24 _inputTick
    ) internal view {
        //check slippage by tick
        if (
            _currentTick > _inputTick + int24(params.tickSlippageBPS()) ||
            _currentTick < _inputTick - int24(params.tickSlippageBPS())
        ) {
            revert(Errors.HIGH_SLIPPAGE);
        }
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */

    ///@notice Burn liquidity per share and compute underlying amount per share
    ///@dev similar to _withdraw on Arrakis
    function _burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    )
        internal
        returns (uint256 burn0_, uint256 burn1_, uint256 fee0_, uint256 fee1_)
    {
        //burn liquidity
        (uint128 liquidity, , , , ) = pool.positions(
            _getPositionID(_lowerTick, _upperTick)
        );
        if (_liquidity > 0) {
            (burn0_, burn1_) = pool.burn(_lowerTick, _upperTick, _liquidity);
        }

        (fee0_, fee1_) = pool.collect(
            address(this),
            _lowerTick,
            _upperTick,
            type(uint128).max,
            type(uint128).max
        );

        emit BurnAndCollectFees(burn0_, burn1_, fee0_, fee1_);
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
