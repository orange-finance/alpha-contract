// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeVaultV1} from "../interfaces/IOrangeVaultV1.sol";
import {IOrangePoolManagerFactory} from "../interfaces/IOrangePoolManagerFactory.sol";
import {IUniswapV3LiquidityPoolManager} from "../interfaces/IUniswapV3LiquidityPoolManager.sol";
import {IAaveLendingPoolManager} from "../interfaces/IAaveLendingPoolManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IOrangeV1Parameters} from "../interfaces/IOrangeV1Parameters.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IFlashLoanRecipient, IERC20} from "../interfaces/IFlashLoanRecipient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {OrangeValidationChecker} from "./OrangeValidationChecker.sol";
import {OrangeERC20, ERC20Decimals} from "./OrangeERC20.sol";

//libraries
import {Errors} from "../libs/Errors.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../libs/uniswap/OracleLibrary.sol";

contract OrangeVaultV1 is IOrangeVaultV1, OrangeERC20, IFlashLoanRecipient, OrangeValidationChecker {
    using SafeERC20 for IERC20;
    using FullMath for uint256;

    /* ========== CONSTANTS ========== */

    /* ========== STORAGES ========== */
    bool public hasPosition;
    int24 public lowerTick;
    int24 public upperTick;
    int24 public stoplossLowerTick;
    int24 public stoplossUpperTick;
    bytes32 flashloanHash;

    /* ========== PARAMETERS ========== */
    IUniswapV3LiquidityPoolManager public liquidityPool;
    IAaveLendingPoolManager public lendingPool;
    IERC20 public token0; //collateral and deposited currency by users
    IERC20 public token1; //debt and hedge target token
    IOrangeV1Parameters public params;

    /* ========== MODIFIER ========== */

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        address _factory,
        address _liquidityTemplate,
        address[] memory _liquidityReferences,
        address _lendingTemplate,
        address[] memory _lendingReferences,
        address _params
    ) OrangeERC20(_name, _symbol) OrangeValidationChecker(_params) {
        // setting adresses and approving
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
        //create liquidity pool
        liquidityPool = IUniswapV3LiquidityPoolManager(
            IOrangePoolManagerFactory(_factory).create(
                _liquidityTemplate,
                address(this),
                _token0,
                _token1,
                new uint256[](0),
                _liquidityReferences
            )
        );
        token0.safeApprove(address(liquidityPool), type(uint256).max);
        token1.safeApprove(address(liquidityPool), type(uint256).max);
        //create lending pool
        lendingPool = IAaveLendingPoolManager(
            IOrangePoolManagerFactory(_factory).create(
                _lendingTemplate,
                address(this),
                _token0,
                _token1,
                new uint256[](0),
                _lendingReferences
            )
        );
        token0.safeApprove(address(lendingPool), type(uint256).max);
        token1.safeApprove(address(lendingPool), type(uint256).max);

        params = IOrangeV1Parameters(_params);
        token0.safeApprove(params.router(), type(uint256).max);
        token1.safeApprove(params.router(), type(uint256).max);
    }

    /* ========== VIEW FUNCTIONS ========== */
    function decimals() external view override returns (uint8) {
        return ERC20Decimals(address(token0)).decimals();
    }

    /// @inheritdoc IOrangeVaultV1
    /// @dev share is propotion of liquidity. Caluculate hedge position and liquidity position except for hedge position.
    function convertToShares(uint256 _assets) external view returns (uint256 shares_) {
        uint256 _supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _assets : _supply.mulDiv(_assets, _totalAssets(lowerTick, upperTick));
    }

    /// @inheritdoc IOrangeVaultV1
    function convertToAssets(uint256 _shares) external view returns (uint256) {
        uint256 _supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.
        return _supply == 0 ? _shares : _shares.mulDiv(_totalAssets(lowerTick, upperTick), _supply);
    }

    /// @inheritdoc IOrangeVaultV1
    function totalAssets() external view returns (uint256) {
        if (totalSupply == 0) return 0;
        return _totalAssets(lowerTick, upperTick);
    }

    ///@notice internal function of totalAssets
    function _totalAssets(int24 _lowerTick, int24 _upperTick) internal view returns (uint256 totalAssets_) {
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(_lowerTick, _upperTick);
        uint256 amount0Debt = lendingPool.balanceOfDebt();
        uint256 amount1Supply = lendingPool.balanceOfCollateral();

        uint256 amount0Balance = _underlyingAssets.liquidityAmount0 +
            _underlyingAssets.accruedFees0 +
            _underlyingAssets.token0Balance;
        uint256 amount1Balance = _underlyingAssets.liquidityAmount1 +
            _underlyingAssets.accruedFees1 +
            _underlyingAssets.token1Balance;
        return _alignTotalAsset(amount0Balance, amount1Balance, amount0Debt, amount1Supply);
    }

    /// @notice Compute total asset price as USDC
    /// @dev Underlying Assets - debt + supply called by _totalAssets
    function _alignTotalAsset(
        uint256 amount0Balance,
        uint256 amount1Balance,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) internal view returns (uint256 totalAlignedAssets) {
        if (amount0Balance < amount0Debt) {
            uint256 amount0deducted = amount0Debt - amount0Balance;
            amount0deducted = OracleLibrary.getQuoteAtTick(
                liquidityPool.getCurrentTick(),
                uint128(amount0deducted),
                address(token0),
                address(token1)
            );
            totalAlignedAssets = amount1Balance + amount1Supply - amount0deducted;
        } else {
            uint256 amount0Added = amount0Balance - amount0Debt;
            if (amount0Added > 0) {
                amount0Added = OracleLibrary.getQuoteAtTick(
                    liquidityPool.getCurrentTick(),
                    uint128(amount0Added),
                    address(token0),
                    address(token1)
                );
            }
            totalAlignedAssets = amount1Balance + amount1Supply + amount0Added;
        }
    }

    /// @inheritdoc IOrangeVaultV1
    function getUnderlyingBalances() external view returns (UnderlyingAssets memory underlyingAssets) {
        return _getUnderlyingBalances(lowerTick, upperTick);
    }

    /// @notice Get the amount of underlying assets
    /// The assets includes added liquidity, fees and left amount in this vault
    /// @dev similar to Arrakis'
    function _getUnderlyingBalances(
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (UnderlyingAssets memory underlyingAssets) {
        uint128 liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        // compute current holdings from liquidity
        if (liquidity > 0) {
            (underlyingAssets.liquidityAmount0, underlyingAssets.liquidityAmount1) = liquidityPool
                .getAmountsForLiquidity(_lowerTick, _upperTick, liquidity);
        }

        (underlyingAssets.accruedFees0, underlyingAssets.accruedFees1) = liquidityPool.getFeesEarned(
            _lowerTick,
            _upperTick
        );

        underlyingAssets.token0Balance = token0.balanceOf(address(this));
        underlyingAssets.token1Balance = token1.balanceOf(address(this));
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @inheritdoc IOrangeVaultV1
    function deposit(
        uint256 _shares,
        address _receiver,
        uint256 _maxAssets,
        bytes32[] calldata _merkleProof
    ) external Allowlisted(_merkleProof) returns (uint256) {
        //validation check
        if (_shares == 0 || _maxAssets == 0) revert(Errors.INVALID_AMOUNT);

        _addDepositCap(_maxAssets);

        //initial deposit
        if (totalSupply == 0) {
            if (_maxAssets < params.minDepositAmount()) {
                revert(Errors.INVALID_DEPOSIT_AMOUNT);
            }
            token1.safeTransferFrom(msg.sender, address(this), _maxAssets);
            _mint(_receiver, _maxAssets - 1e4);
            _mint(address(0), 1e4); // for manipulation resistance
            return _maxAssets - 1e4;
        }

        //take current positions.
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(lowerTick, upperTick);
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);

        //calculate additional Aave position and Contract balances by shares
        Positions memory _additionalPosition = _computeTargetPositionByShares(
            lendingPool.balanceOfDebt(),
            lendingPool.balanceOfCollateral(),
            _underlyingAssets.token0Balance + _underlyingAssets.accruedFees0, //including pending fees
            _underlyingAssets.token1Balance + _underlyingAssets.accruedFees1, //including pending fees
            _shares,
            totalSupply
        );

        //calculate additional amounts based on liquidity by shares
        uint128 _additionalLiquidity = SafeCast.toUint128(uint256(_liquidity).mulDiv(_shares, totalSupply));

        //transfer USDC to this contract
        token1.safeTransferFrom(msg.sender, address(this), _maxAssets);

        //append position
        _depositFlashloan(
            _additionalPosition, //Aave & Contract Balances
            _additionalLiquidity, //Uni
            _maxAssets, //USDC from User
            _receiver
        );

        // mint share to receiver
        _mint(_receiver, _shares);

        _emitAction(ActionType.DEPOSIT, _receiver);
        return _shares;
    }

    function _depositFlashloan(
        Positions memory _additionalPosition,
        uint128 _additionalLiquidity,
        uint256 _maxAssets,
        address _receiver
    ) internal {
        uint256 _additionalLiquidityAmount0;
        uint256 _additionalLiquidityAmount1;
        if (_additionalLiquidity > 0) {
            (_additionalLiquidityAmount0, _additionalLiquidityAmount1) = liquidityPool.getAmountsForLiquidity(
                lowerTick,
                upperTick,
                _additionalLiquidity
            );
        }

        //The case of overhedge (debtETH > liqETH + balanceETH)
        if (_additionalPosition.debtAmount1 > _additionalLiquidityAmount0 + _additionalPosition.token0Balance) {
            //execute flashloan

            /**
             * Flashloan USDC. append positions. swap WETH=>USDC (leave some WETH for _additionalPosition.token0Balance ). Return the loan.
             */
            _makeFlashLoan(
                token1,
                _additionalPosition.collateralAmount0 + _additionalLiquidityAmount1 + 1,
                abi.encode(
                    FlashloanType.DEPOSIT_OVERHEDGE,
                    _additionalPosition,
                    _additionalLiquidity,
                    _maxAssets,
                    _receiver
                )
            );
        } else {
            //underhedge

            /**
             * Flashloan ETH. append positions. swap USDC=>WETH (swap some more ETH for _additionalPosition.token0Balance). Return the loan.
             */
            _makeFlashLoan(
                token0,
                _additionalPosition.debtAmount1 > _additionalLiquidityAmount0
                    ? 0
                    : _additionalLiquidityAmount0 - _additionalPosition.debtAmount1 + 1,
                abi.encode(
                    FlashloanType.DEPOSIT_UNDERHEDGE,
                    _additionalPosition,
                    _additionalLiquidity,
                    _maxAssets,
                    _receiver
                )
            );
        }
    }

    /// @inheritdoc IOrangeVaultV1
    function redeem(
        uint256 _shares,
        address _receiver,
        address,
        uint256 _minAssets
    ) external Lockup returns (uint256 returnAssets_) {
        //validation
        if (_shares == 0) {
            revert(Errors.INVALID_AMOUNT);
        }

        uint256 _totalSupply = totalSupply;
        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;

        //burn
        _burn(_receiver, _shares);

        // Remove liquidity by shares and collect all fees
        (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) = _redeemLiqidityByShares(
            _shares,
            _totalSupply,
            _lowerTick,
            _upperTick
        );

        //compute redeem positions except liquidity
        //because liquidity is computed by shares
        //so `token0.balanceOf(address(this)) - _burnedLiquidityAmount0` means remaining balance and colleted fee
        Positions memory _redeemPosition = _computeTargetPositionByShares(
            lendingPool.balanceOfDebt(),
            lendingPool.balanceOfCollateral(),
            token0.balanceOf(address(this)) - _burnedLiquidityAmount0,
            token1.balanceOf(address(this)) - _burnedLiquidityAmount1,
            _shares,
            _totalSupply
        );

        // `_redeemedBalances` are currently hold balances in this vault and will transfer to receiver
        uint _redeemableToken0 = _redeemPosition.token0Balance + _burnedLiquidityAmount0;
        uint _redeemableToken1 = _redeemPosition.token1Balance + _burnedLiquidityAmount1;

        uint256 _flashBorrowToken0;
        if (_redeemPosition.debtAmount1 >= _redeemableToken0) {
            unchecked {
                _flashBorrowToken0 = _redeemPosition.debtAmount1 - _redeemableToken0;
            }
        } else {
            // swap surplus ETH to return receiver as USDC
            _redeemableToken1 += _swapAmountIn(true, _redeemableToken0 - _redeemPosition.debtAmount1);
        }

        // memorize balance of token1 to be remained in vault
        uint256 _unRedeemableBalance1 = token1.balanceOf(address(this)) - _redeemableToken1;

        // execute flashloan (repay ETH and withdraw USDC in callback function `receiveFlashLoan`)
        _makeFlashLoan(
            token0,
            _flashBorrowToken0,
            abi.encode(FlashloanType.REDEEM, _redeemPosition.debtAmount1, _redeemPosition.collateralAmount0)
        );

        returnAssets_ = token1.balanceOf(address(this)) - _unRedeemableBalance1;

        // Transfer USDC from Vault to Receiver
        if (returnAssets_ < _minAssets) {
            revert(Errors.LESS_AMOUNT);
        }
        token1.safeTransfer(_receiver, returnAssets_);
        _reduceDepositCap(returnAssets_);

        _emitAction(ActionType.REDEEM, _receiver);
    }

    ///@notice remove liquidity by share ratio and collect all fees
    ///@dev called by redeem
    function _redeemLiqidityByShares(
        uint256 _shares,
        uint256 _totalSupply,
        int24 _lowerTick,
        int24 _upperTick
    ) internal returns (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) {
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(_lowerTick, _upperTick);
        //unnecessary to check _totalSupply == 0 because an error occurs in redeem before calling this function
        uint128 _burnLiquidity = SafeCast.toUint128(uint256(_liquidity).mulDiv(_shares, _totalSupply));
        (_burnedLiquidityAmount0, _burnedLiquidityAmount1) = _burnAndCollectFees(
            _lowerTick,
            _upperTick,
            _burnLiquidity
        );
    }

    /// @inheritdoc IOrangeVaultV1
    function stoploss(int24 _inputTick) external returns (uint256) {
        if (!params.strategists(msg.sender) && params.gelatoExecutor() != msg.sender) {
            revert(Errors.ONLY_STRATEGISTS_OR_GELATO);
        }

        if (totalSupply == 0) return 0;

        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;
        _checkTickSlippage(liquidityPool.getCurrentTick(), _inputTick);

        // 1. Remove liquidity
        // 2. Collect fees
        uint128 liquidity = liquidityPool.getCurrentLiquidity(_lowerTick, _upperTick);
        if (liquidity > 0) {
            _burnAndCollectFees(_lowerTick, _upperTick, liquidity);
        }

        uint256 _repayingDebt = lendingPool.balanceOfDebt();
        uint256 _balanceToken0 = token0.balanceOf(address(this));
        uint256 _withdrawingCollateral = lendingPool.balanceOfCollateral();

        // Flashloan to borrow Repay ETH
        uint256 _flashBorrowToken0;
        if (_repayingDebt > _balanceToken0) {
            unchecked {
                _flashBorrowToken0 = _repayingDebt - _balanceToken0;
            }
        }

        // execute flashloan (repay ETH and withdraw USDC in callback function `receiveFlashLoan`)
        _makeFlashLoan(
            token0,
            _flashBorrowToken0,
            abi.encode(FlashloanType.REDEEM, _repayingDebt, _withdrawingCollateral)
        );

        // swap remaining all ETH to USDC
        _balanceToken0 = token0.balanceOf(address(this));
        if (_balanceToken0 > 0) {
            _swapAmountIn(true, _balanceToken0);
        }

        _emitAction(ActionType.STOPLOSS, msg.sender);
        hasPosition = false;
        return token1.balanceOf(address(this));
    }

    /// @inheritdoc IOrangeVaultV1
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        Positions memory _targetPosition,
        uint128 _minNewLiquidity
    ) external {
        if (!params.strategists(msg.sender)) {
            revert(Errors.ONLY_STRATEGISTS);
        }
        //validation of tickSpacing
        liquidityPool.validateTicks(_newLowerTick, _newUpperTick);
        //TODO _newStoplossLowerTick is unused
        liquidityPool.validateTicks(_newStoplossLowerTick, _newStoplossUpperTick);

        int24 _lowerTick = lowerTick;
        int24 _upperTick = upperTick;

        // 1. burn and collect fees
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(_lowerTick, _upperTick);
        _burnAndCollectFees(_lowerTick, _upperTick, _liquidity);

        // Update storage of ranges
        _lowerTick = _newLowerTick; //memory
        _upperTick = _newUpperTick; //memory
        lowerTick = _newLowerTick;
        upperTick = _newUpperTick;
        stoplossLowerTick = _newStoplossLowerTick;
        stoplossUpperTick = _newStoplossUpperTick;

        if (totalSupply == 0) {
            return;
        }

        // 2. get current position
        Positions memory _currentPosition = Positions(
            lendingPool.balanceOfDebt(),
            lendingPool.balanceOfCollateral(),
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        // 4. execute hedge
        _executeHedgeRebalance(_currentPosition, _targetPosition);

        // 5. Add liquidity
        uint128 _targetLiquidity = _addLiquidityInRebalance(
            _lowerTick,
            _upperTick,
            _targetPosition.token0Balance, // amount of token0 to be added to Uniswap
            _targetPosition.token1Balance // amount of token1 to be added to Uniswap
        );
        if (_targetLiquidity < _minNewLiquidity) {
            revert(Errors.LESS_LIQUIDITY);
        }
        //TODO is LTV check necessary?

        _emitAction(ActionType.REBALANCE, msg.sender);

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
            _currentPosition.collateralAmount0 == _targetPosition.collateralAmount0 ||
            _currentPosition.debtAmount1 == _targetPosition.debtAmount1
        ) {
            // if originally collateral is 0, through this function
            if (_currentPosition.collateralAmount0 == 0) return;
            revert(Errors.EQUAL_COLLATERAL_OR_DEBT);
        }
        unchecked {
            if (
                _currentPosition.collateralAmount0 < _targetPosition.collateralAmount0 &&
                _currentPosition.debtAmount1 < _targetPosition.debtAmount1
            ) {
                // case1 supply and borrow
                uint256 _supply = _targetPosition.collateralAmount0 - _currentPosition.collateralAmount0; //uncheckable

                if (_supply > _currentPosition.token1Balance) {
                    // swap (if necessary)
                    _swapAmountOut(
                        true,
                        _supply - _currentPosition.token1Balance //uncheckable
                    );
                }
                lendingPool.supply(_supply);

                // borrow
                uint256 _borrow = _targetPosition.debtAmount1 - _currentPosition.debtAmount1; //uncheckable
                lendingPool.borrow(_borrow);
            } else {
                if (_currentPosition.debtAmount1 > _targetPosition.debtAmount1) {
                    // case2 repay
                    uint256 _repay = _currentPosition.debtAmount1 - _targetPosition.debtAmount1; //uncheckable

                    // swap (if necessary)
                    if (_repay > _currentPosition.token0Balance) {
                        _swapAmountOut(
                            false,
                            _repay - _currentPosition.token0Balance //uncheckable
                        );
                    }
                    lendingPool.repay(_repay);

                    if (_currentPosition.collateralAmount0 < _targetPosition.collateralAmount0) {
                        // case2_1 repay and supply
                        uint256 _supply = _targetPosition.collateralAmount0 - _currentPosition.collateralAmount0; //uncheckable
                        lendingPool.supply(_supply);
                    } else {
                        // case2_2 repay and withdraw
                        uint256 _withdraw = _currentPosition.collateralAmount0 - _targetPosition.collateralAmount0; //uncheckable. //possibly, equal
                        lendingPool.withdraw(_withdraw);
                    }
                } else {
                    // case3 borrow and withdraw
                    uint256 _borrow = _targetPosition.debtAmount1 - _currentPosition.debtAmount1; //uncheckable. //possibly, equal
                    lendingPool.borrow(_borrow);
                    // withdraw should be the only option here.
                    uint256 _withdraw = _currentPosition.collateralAmount0 - _targetPosition.collateralAmount0; //should be uncheckable. //possibly, equal
                    lendingPool.withdraw(_withdraw);
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

        targetLiquidity_ = liquidityPool.getLiquidityForAmounts(
            _lowerTick,
            _upperTick,
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        liquidityPool.mint(_lowerTick, _upperTick, targetLiquidity_);
    }

    /// @inheritdoc IOrangeVaultV1
    function emitAction() external {
        _emitAction(ActionType.MANUAL, msg.sender);
    }

    function _emitAction(ActionType _actionType, address _caller) internal {
        emit Action(_actionType, _caller, _totalAssets(lowerTick, upperTick), totalSupply);
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    ///@notice Compute target position by shares
    ///@dev called by deposit and redeem
    function _computeTargetPositionByShares(
        uint256 _debtAmount1,
        uint256 _collateralAmount0,
        uint256 _token0Balance,
        uint256 _token1Balance,
        uint256 _shares,
        uint256 _totalSupply
    ) internal pure returns (Positions memory _position) {
        _position.debtAmount1 = _debtAmount1.mulDiv(_shares, _totalSupply);
        _position.collateralAmount0 = _collateralAmount0.mulDiv(_shares, _totalSupply);
        _position.token0Balance = _token0Balance.mulDiv(_shares, _totalSupply);
        _position.token1Balance = _token1Balance.mulDiv(_shares, _totalSupply);
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

    ///@notice get slippage and parameters in _swapAmountOut and _swapAmountIn
    /// return parameters (address tokenIn, address tokenOut, uint160 _sqrtPriceLimitX96)
    function _getSlippageOnSwapRouter(bool _zeroForOne) internal view returns (address, address, uint160) {
        // (uint160 _sqrtRatioX96, , , , , , ) = liquidityPool.pool().slot0();
        return
            (_zeroForOne)
                ? (
                    address(token0),
                    address(token1),
                    // (_sqrtRatioX96 * (MAGIC_SCALE_1E4 - params.slippageBPS())) / MAGIC_SCALE_1E4
                    0
                )
                : (
                    address(token1),
                    address(token0),
                    // (_sqrtRatioX96 * (MAGIC_SCALE_1E4 + params.slippageBPS())) / MAGIC_SCALE_1E4
                    0
                );
    }

    ///@notice Swap exact amount out
    function _swapAmountOut(bool _zeroForOne, uint256 _amountOut) internal returns (uint256 amountIn_) {
        if (_amountOut == 0) return 0;
        (address tokenIn, address tokenOut, uint160 _sqrtPriceLimitX96) = _getSlippageOnSwapRouter(_zeroForOne);
        ISwapRouter.ExactOutputSingleParams memory _params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: params.routerFee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: _sqrtPriceLimitX96
        });
        amountIn_ = ISwapRouter(params.router()).exactOutputSingle(_params);
    }

    ///@notice Swap exact amount in
    function _swapAmountIn(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        if (_amountIn == 0) return 0;
        (address tokenIn, address tokenOut, uint160 _sqrtPriceLimitX96) = _getSlippageOnSwapRouter(_zeroForOne);
        ISwapRouter.ExactInputSingleParams memory _params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: params.routerFee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: _sqrtPriceLimitX96
        });
        amountOut_ = ISwapRouter(params.router()).exactInputSingle(_params);
    }

    function _makeFlashLoan(IERC20 _token, uint256 _amount, bytes memory _userData) internal {
        IERC20[] memory _tokensFlashloan = new IERC20[](1);
        _tokensFlashloan[0] = _token;
        uint256[] memory _amountsFlashloan = new uint256[](1);
        _amountsFlashloan[0] = _amount;
        flashloanHash = keccak256(_userData); //set stroage for callback
        IVault(params.balancer()).flashLoan(this, _tokensFlashloan, _amountsFlashloan, _userData);
    }

    ///@notice Remove liquidity from Uniswap and collect fees
    function _burnAndCollectFees(
        int24 _lowerTick,
        int24 _upperTick,
        uint128 _liquidity
    ) internal returns (uint256 burn0_, uint256 burn1_) {
        if (_liquidity > 0) {
            (burn0_, burn1_) = liquidityPool.burn(_lowerTick, _upperTick, _liquidity);
        }
        liquidityPool.collect(_lowerTick, _upperTick);
    }

    /* ========== FLASHLOAN CALLBACK ========== */
    ///@notice There are two types of _userData, determined by the FlashloanType (REDEEM or DEPOSIT_OVERHEDGE/UNDERHEDGE).
    function receiveFlashLoan(
        IERC20[] memory _tokens,
        uint256[] memory _amounts,
        uint256[] memory,
        bytes memory _userData
    ) external {
        if (msg.sender != params.balancer()) revert(Errors.ONLY_BALANCER_VAULT);
        if (flashloanHash == bytes32(0) || flashloanHash != keccak256(_userData)) revert(Errors.INVALID_FLASHLOAN_HASH);
        flashloanHash = bytes32(0); //clear storage

        uint8 _flashloanType = abi.decode(_userData, (uint8));
        if (_flashloanType == uint8(FlashloanType.REDEEM)) {
            (, uint256 _amount0, uint256 _amount1) = abi.decode(_userData, (uint8, uint256, uint256));

            // Repay ETH
            lendingPool.repay(_amount0);
            // Withdraw USDC as collateral
            lendingPool.withdraw(_amount1);

            //swap to repay flashloan
            if (_amounts[0] > 0) {
                bool _zeroForOne = (address(_tokens[0]) == address(token0)) ? false : true;
                // swap USDC to ETH to repay flashloan
                _swapAmountOut(_zeroForOne, _amounts[0]);
            }
        } else {
            _depositInFlashloan(_flashloanType, _amounts[0], _userData);
        }
        //repay flashloan
        IERC20(_tokens[0]).safeTransfer(params.balancer(), _amounts[0]);
    }

    function _depositInFlashloan(uint8 _flashloanType, uint256 borrowFlashloanAmount, bytes memory _userData) internal {
        (, Positions memory _positions, uint128 _additionalLiquidity, uint256 _maxAssets, address _receiver) = abi
            .decode(_userData, (uint8, Positions, uint128, uint256, address));
        /**
         * appending positions
         * 1. collateral USDC
         * 2. borrow ETH
         * 3. liquidity ETH
         * 4. liquidity USDC
         * 5. additional ETH (in the Vault)
         * 6. additional USDC (in the Vault)
         */

        //Supply USDC and Borrow ETH (#1 and #2)
        lendingPool.supply(_positions.collateralAmount0);
        lendingPool.borrow(_positions.debtAmount1);

        //Add Liquidity (#3 and #4)
        uint _additionalLiquidityAmount0;
        uint _additionalLiquidityAmount1;

        (_additionalLiquidityAmount0, _additionalLiquidityAmount1) = liquidityPool.mint(
            lowerTick,
            upperTick,
            _additionalLiquidity
        );

        uint _actualUsedAmountUSDC;
        if (_flashloanType == uint8(FlashloanType.DEPOSIT_OVERHEDGE)) {
            // Calculate the amount of surplus ETH and swap to USDC (Leave some ETH for #5)
            uint256 _surplusAmountETH = _positions.debtAmount1 -
                (_additionalLiquidityAmount0 + _positions.token0Balance);
            uint256 _amountOutFromSurplusETHSale = _swapAmountIn(true, _surplusAmountETH);

            _actualUsedAmountUSDC = borrowFlashloanAmount + _positions.token1Balance - _amountOutFromSurplusETHSale;
        } else if (_flashloanType == uint8(FlashloanType.DEPOSIT_UNDERHEDGE)) {
            // Calculate the amount of ETH needed to be swapped to repay the loan, then swap USDC=>ETH (Swap more ETH for #5)
            uint256 ethAmountToSwap = _additionalLiquidityAmount0 + _positions.token0Balance - _positions.debtAmount1;
            uint256 usdcAmtUsedForEth = _swapAmountOut(false, ethAmountToSwap);

            _actualUsedAmountUSDC =
                _positions.collateralAmount0 +
                _additionalLiquidityAmount1 +
                _positions.token1Balance +
                usdcAmtUsedForEth;
        }

        //Refund the unspent USDC (Leave some USDC for #6)
        if (_maxAssets < _actualUsedAmountUSDC) revert(Errors.LESS_MAX_ASSETS);
        unchecked {
            uint256 _refundAmountUSDC = _maxAssets - _actualUsedAmountUSDC;
            if (_refundAmountUSDC > 0) token1.safeTransfer(_receiver, _refundAmountUSDC);
        }
    }
}
