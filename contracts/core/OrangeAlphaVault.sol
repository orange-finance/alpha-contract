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

    modifier onlyAdministrators() {
        if (!params.administrators(msg.sender)) {
            revert(Errors.ONLY_ADMINISTRATOR);
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
        if (totalSupply() == 0) return 0;
        return _totalAssets(_getTicksByStorage());
    }

    ///@notice internal function of totalAssets

    /**
     * @notice Compute total asset price as USDC
     * @dev Underlying Assets - debt + supply
     */
    function _totalAssets(Ticks memory _ticks)
        internal
        view
        returns (uint256 totalAssets_)
    {
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

        if (amount0Current < amount0Debt) {
            uint256 amount0deducted = amount0Debt - amount0Current;
            amount0deducted = OracleLibrary.getQuoteAtTick(
                _ticks.currentTick,
                uint128(amount0deducted),
                address(token0),
                address(token1)
            );
            totalAssets_ = amount1Current + amount1Supply - amount0deducted;
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
            totalAssets_ = amount1Current + amount1Supply + amount0Added;
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

    /// @inheritdoc IOrangeAlphaVault
    function getRebalancedLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick
    ) external view returns (uint128 liquidity_) {
        Ticks memory _ticks = _getTicksByStorage();
        uint256 _assets = _totalAssets(_ticks);
        (uint256 _supply, uint256 _borrow) = _computeSupplyAndBorrow(
            _assets,
            _ticks.currentTick,
            _newLowerTick,
            _newUpperTick,
            _newStoplossLowerTick,
            _newStoplossUpperTick
        );
        uint256 remainingAmount = _assets - _supply;
        //compute liquidity
        liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.currentTick.getSqrtRatioAtTick(),
            _newLowerTick.getSqrtRatioAtTick(),
            _newUpperTick.getSqrtRatioAtTick(),
            _borrow,
            remainingAmount
        );
        // console2.log(liquidity_, "liquidity_");
    }

    /// @notice Compute collateral and borrow amount
    function _computeSupplyAndBorrow(
        uint256 _assets,
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick,
        int24,
        int24 _stoplossUpperTick
    ) internal view returns (uint256 supply_, uint256 borrow_) {
        if (_assets == 0) return (0, 0);

        //compute LTV
        //LTV is caluculated by upper wider range
        int24 _upperTickForLtv = (_upperTick > _stoplossUpperTick)
            ? _upperTick
            : _stoplossUpperTick;
        uint256 _ltv = _getLtvByRange(_currentTick, _upperTickForLtv);

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

        supply_ =
            (_assets * MAGIC_SCALE_1E8) /
            (MAGIC_SCALE_1E8 + _ltv.mulDiv(_amount1, _amount0Usdc));

        uint256 _borrowUsdc = supply_.mulDiv(_ltv, MAGIC_SCALE_1E8);
        //borrowing usdc amount to weth
        borrow_ = OracleLibrary.getQuoteAtTick(
            _currentTick,
            uint128(_borrowUsdc),
            address(token1),
            address(token0)
        );
        // console2.log(supply_, "supply_");
        // console2.log(borrow_, "borrow_");
    }

    ///@notice Get LTV by current and range prices
    ///@dev called by _computeSupplyAndBorrow. maxLtv * (current price / upper price)
    function _getLtvByRange(int24 _currentTick, int24 _upperTick)
        internal
        view
        returns (uint256 ltv_)
    {
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
        uint256 _assets,
        address _receiver,
        uint256 _minShares
    ) external onlyPeriphery returns (uint256) {
        //validation check
        if (_assets == 0 || _minShares == 0) revert(Errors.INVALID_AMOUNT);

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
        ) = _computeHedgeAndLiquidityByShares(_minShares, _ticks);

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

        //mint to receiver
        _mint(_receiver, _minShares);

        _emitAction(1, _ticks);
        return _minShares;
    }

    ///@dev called by deposit
    function _computeHedgeAndLiquidityByShares(
        uint256 _minShares,
        Ticks memory _ticks
    )
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
                _ticks.lowerTick.getSqrtRatioAtTick(),
                _ticks.upperTick.getSqrtRatioAtTick(),
                _targetLiquidity
            );
    }

    ///@notice swap surplus amount0 or amount1
    ///@dev called by _computeHedgeAndLiquidityByShares
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
            revert(Errors.INVALID_AMOUNT);
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
            uint256 _fee1
        ) = _burnAndCollectFees(
                _ticks.lowerTick,
                _ticks.upperTick,
                liquidityBurned_
            );
        _fee0 = FullMath.mulDiv(_shares, _fee0, _totalSupply);
        _fee1 = FullMath.mulDiv(_shares, _fee1, _totalSupply);
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
    function removeAllPosition(int24 _inputTick) external onlyAdministrators {
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
    }

    /// @inheritdoc IOrangeAlphaVault
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint128 _minNewLiquidity
    ) external onlyAdministrators {
        //validation of tickSpacing
        _validateTicks(_newLowerTick, _newUpperTick);
        _validateTicks(_newStoplossLowerTick, _newStoplossUpperTick);

        Ticks memory _ticks = _getTicksByStorage();
        //if not stoplossed, removeAllPosition
        if (!stoplossed) {
            _removeAllPosition(_ticks);
        }

        // 1. Remove liquidity and Collect fees
        (uint128 liquidity, , , , ) = pool.positions(
            _getPositionID(_ticks.lowerTick, _ticks.upperTick)
        );
        if (liquidity > 0) {
            _burnAndCollectFees(_ticks.lowerTick, _ticks.upperTick, liquidity);
        }

        // 2. Update storage of ranges
        _ticks.lowerTick = _newLowerTick; //memory
        _ticks.upperTick = _newUpperTick; //memory
        lowerTick = _newLowerTick;
        upperTick = _newUpperTick;
        stoplossLowerTick = _newStoplossLowerTick;
        stoplossUpperTick = _newStoplossUpperTick;

        // 3. Supply or borrow to lending
        uint256 _assets = _totalAssets(_ticks);
        (uint256 _supply, uint256 _borrow) = _computeSupplyAndBorrow(
            _assets,
            _ticks.currentTick,
            _newLowerTick,
            _newUpperTick,
            _newStoplossLowerTick,
            _newStoplossUpperTick
        );
        if (_supply > 0) {
            aave.supply(address(token1), _supply, address(this), 0);
        }
        if (_borrow > 0) {
            aave.borrow(address(token0), _borrow, 2, 0, address(this));
        }

        // 4. Add liquidity
        uint256 _remainingAmount1 = _assets - _supply;
        uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
            _ticks.currentTick.getSqrtRatioAtTick(),
            _ticks.lowerTick.getSqrtRatioAtTick(),
            _ticks.upperTick.getSqrtRatioAtTick(),
            _borrow,
            _remainingAmount1
        );
        if (_liquidity < _minNewLiquidity) {
            revert(Errors.LESS_LIQUIDITY);
        }
        pool.mint(
            address(this),
            _ticks.lowerTick,
            _ticks.upperTick,
            _liquidity,
            ""
        );

        _emitAction(3, _ticks);

        //reset stoplossed
        stoplossed = false;
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
    function _getPositionID(int24 _lowerTick, int24 _upperTick)
        internal
        view
        returns (bytes32 positionID)
    {
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

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */

    ///@notice Burn liquidity per share and compute underlying amount per share
    ///@dev similar to _withdraw on Arrakis
    function _burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    )
        internal
        returns (
            uint256 burn0_,
            uint256 burn1_,
            uint256 feeAndRemaining0_,
            uint256 feeAndRemaining1_
        )
    {
        //collect fees
        uint256 _preBalance0 = token0.balanceOf(address(this));
        uint256 _preBalance1 = token1.balanceOf(address(this));

        (uint256 _fee0, uint256 _fee1) = pool.collect(
            address(this),
            _lowerTick,
            _upperTick,
            type(uint128).max,
            type(uint128).max
        );
        feeAndRemaining0_ = _preBalance0 + _fee0;
        feeAndRemaining1_ = _preBalance1 + _fee1;

        //burn liquidity
        if (_liquidity > 0) {
            (burn0_, burn1_) = pool.burn(_lowerTick, _upperTick, _liquidity);
        }

        emit BurnAndCollectFees(burn0_, burn1_, _fee0, _fee1);
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
            revert(Errors.ONLY_CALLBACK_CALLER);
        }

        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
