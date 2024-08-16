// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeStorageV1Initializable} from "@src/coreV1/proxy/OrangeStorageV1Initializable.sol";

//interfaces
import {IOrangeVaultV1} from "@src/interfaces/IOrangeVaultV1.sol";
import {ILiquidityPoolManager} from "@src/interfaces/ILiquidityPoolManager.sol";
import {ILendingPoolManager} from "@src/interfaces/ILendingPoolManager.sol";

//libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UniswapRouterSwapper, ISwapRouter} from "@src/libs/UniswapRouterSwapper.sol";
import {BalancerFlashloan, IBalancerVault, IBalancerFlashLoanRecipient, IERC20} from "@src/libs/BalancerFlashloan.sol";
import {ErrorsV1} from "@src/coreV1/ErrorsV1.sol";

contract OrangeStrategyImplV1Initializable is OrangeStorageV1Initializable {
    using SafeERC20 for IERC20;
    using UniswapRouterSwapper for ISwapRouter;
    using BalancerFlashloan for IBalancerVault;

    /**
     * @dev It's okay to lock initialize state with constructor
     * because this only accepts delegate call so that doesn't have own state actually.
     */
    constructor() initializer {}

    /* ========== EXTERNAL FUNCTIONS ========== */
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        IOrangeVaultV1.Positions memory _targetPosition,
        uint128 _minNewLiquidity
    ) external {
        int24 _currentLowerTick = lowerTick;
        int24 _currentUpperTick = upperTick;

        // update storage of ranges
        lowerTick = _newLowerTick;
        upperTick = _newUpperTick;
        hasPosition = true;

        // validation of tickSpacing
        ILiquidityPoolManager(liquidityPool).validateTicks(_newLowerTick, _newUpperTick);

        // 1. burn and collect fees
        uint128 _liquidity = ILiquidityPoolManager(liquidityPool).getCurrentLiquidity(
            _currentLowerTick,
            _currentUpperTick
        );
        ILiquidityPoolManager(liquidityPool).burnAndCollect(_currentLowerTick, _currentUpperTick, _liquidity);

        // 2. get current position
        IOrangeVaultV1.Positions memory _currentPosition = IOrangeVaultV1.Positions(
            ILendingPoolManager(lendingPool).balanceOfCollateral(),
            ILendingPoolManager(lendingPool).balanceOfDebt(),
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );

        // 3. execute hedge
        _executeHedgeRebalance(_currentPosition, _targetPosition);

        // 4. add liquidity
        uint128 _addedLiquidity = _addLiquidityInRebalance(
            _newLowerTick,
            _newUpperTick,
            _targetPosition.token0Balance, // amount of token0 to be added to Uniswap
            _targetPosition.token1Balance // amount of token1 to be added to Uniswap
        );

        // check if rebalance has done as expected or not
        if (_addedLiquidity < _minNewLiquidity) {
            revert(ErrorsV1.LESS_LIQUIDITY);
        }

        // emit event
        IOrangeVaultV1(address(this)).emitAction(IOrangeVaultV1.ActionType.REBALANCE);
    }

    function stoploss(int24 _inputTick) external {
        _checkTickSlippage(ILiquidityPoolManager(liquidityPool).getCurrentTick(), _inputTick);

        hasPosition = false;

        // 1. Remove liquidity & Collect Fees
        uint128 liquidity = ILiquidityPoolManager(liquidityPool).getCurrentLiquidity(lowerTick, upperTick);
        if (liquidity > 0) {
            ILiquidityPoolManager(liquidityPool).burnAndCollect(lowerTick, upperTick, liquidity);
        }

        (uint256 _withdrawingToken0, uint256 _repayingToken1) = ILendingPoolManager(lendingPool).balances();
        uint256 _vaultAmount1 = token1.balanceOf(address(this));

        // 2. Flashloan token1 to repay the Debt (Token1)
        uint256 _flashLoanAmount1;
        if (_repayingToken1 > _vaultAmount1) {
            unchecked {
                _flashLoanAmount1 = _repayingToken1 - _vaultAmount1;
            }
        }

        // execute flashloan (repay Token1 and withdraw Token0 in callback function `receiveFlashLoan`)
        bytes memory _userData = abi.encode(IOrangeVaultV1.FlashloanType.STOPLOSS, _repayingToken1, _withdrawingToken0);
        flashloanHash = keccak256(_userData); //set stroage for callback
        IBalancerVault(balancer).makeFlashLoan(
            IBalancerFlashLoanRecipient(address(this)),
            token1,
            _flashLoanAmount1,
            _userData
        );

        // 3. Swap remaining all Token1 for Token0
        _vaultAmount1 = token1.balanceOf(address(this));
        if (_vaultAmount1 > 0) {
            ISwapRouter(router).swapAmountIn(
                address(token1), //In
                address(token0), //Out
                routerFee,
                _vaultAmount1
            );
        }

        // emit event
        IOrangeVaultV1(address(this)).emitAction(IOrangeVaultV1.ActionType.STOPLOSS);
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    ///@notice Check slippage by tick
    function _checkTickSlippage(int24 _currentTick, int24 _inputTick) internal view {
        if (
            _currentTick > _inputTick + int24(params.tickSlippageBPS()) ||
            _currentTick < _inputTick - int24(params.tickSlippageBPS())
        ) {
            revert(ErrorsV1.HIGH_SLIPPAGE);
        }
    }

    /// @notice execute hedge by changing collateral or debt amount
    /// @dev called by rebalance.
    /// @dev currently, rebalance doesn't support flashloan, so this may swap multiple times.
    function _executeHedgeRebalance(
        IOrangeVaultV1.Positions memory _currentPosition,
        IOrangeVaultV1.Positions memory _targetPosition
    ) internal {
        // skip special situation below to keep the code simple.
        if (
            _currentPosition.collateralAmount0 == _targetPosition.collateralAmount0 ||
            _currentPosition.debtAmount1 == _targetPosition.debtAmount1
        ) {
            // if originally collateral is 0, through this function
            if (_currentPosition.collateralAmount0 == 0) return;
            revert(ErrorsV1.EQUAL_COLLATERAL_OR_DEBT);
        }

        // start rebalance.
        unchecked {
            if (
                _currentPosition.collateralAmount0 < _targetPosition.collateralAmount0 &&
                _currentPosition.debtAmount1 < _targetPosition.debtAmount1
            ) {
                // Case1: Supply & Borrow

                // 1.supply
                uint256 _supply0 = _targetPosition.collateralAmount0 - _currentPosition.collateralAmount0;

                // swap (if necessary)
                if (_supply0 > _currentPosition.token0Balance) {
                    ISwapRouter(router).swapAmountOut(
                        address(token1),
                        address(token0),
                        routerFee,
                        _supply0 - _currentPosition.token0Balance
                    );
                }

                ILendingPoolManager(lendingPool).supply(_supply0);

                // 2.borrow
                uint256 _borrow1 = _targetPosition.debtAmount1 - _currentPosition.debtAmount1;
                ILendingPoolManager(lendingPool).borrow(_borrow1);
            } else {
                if (_currentPosition.debtAmount1 > _targetPosition.debtAmount1) {
                    // Case2: Repay & (Supply or Withdraw)

                    // 1. Repay
                    uint256 _repay1 = _currentPosition.debtAmount1 - _targetPosition.debtAmount1;

                    // swap (if necessary)
                    if (_repay1 > _currentPosition.token1Balance) {
                        ISwapRouter(router).swapAmountOut(
                            address(token0), //In
                            address(token1), //Out
                            routerFee,
                            _repay1 - _currentPosition.token1Balance
                        );
                    }
                    ILendingPoolManager(lendingPool).repay(_repay1);

                    // check which of supply or withdraw comes after
                    if (_currentPosition.collateralAmount0 < _targetPosition.collateralAmount0) {
                        // 2. Supply

                        uint256 _supply0 = _targetPosition.collateralAmount0 - _currentPosition.collateralAmount0;
                        ILendingPoolManager(lendingPool).supply(_supply0);
                    } else {
                        // 2. Withdraw
                        uint256 _withdraw0 = _currentPosition.collateralAmount0 - _targetPosition.collateralAmount0;
                        ILendingPoolManager(lendingPool).withdraw(_withdraw0);
                    }
                } else {
                    // Case3: Borrow and Withdraw

                    // 1. borrow
                    uint256 _borrow1 = _targetPosition.debtAmount1 - _currentPosition.debtAmount1;
                    ILendingPoolManager(lendingPool).borrow(_borrow1);

                    // 2. withdraw
                    uint256 _withdraw0 = _currentPosition.collateralAmount0 - _targetPosition.collateralAmount0;
                    ILendingPoolManager(lendingPool).withdraw(_withdraw0);
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
                    ISwapRouter(router).swapAmountIn(
                        address(token0),
                        address(token1),
                        routerFee,
                        _balance0 - _targetAmount0
                    );
                } else if (_balance1 > _targetAmount1) {
                    ISwapRouter(router).swapAmountIn(
                        address(token1),
                        address(token0),
                        routerFee,
                        _balance1 - _targetAmount1
                    );
                }
            }
        }

        targetLiquidity_ = ILiquidityPoolManager(liquidityPool).getLiquidityForAmounts(
            _lowerTick,
            _upperTick,
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this))
        );
        if (targetLiquidity_ > 0) {
            ILiquidityPoolManager(liquidityPool).mint(_lowerTick, _upperTick, targetLiquidity_);
        }
    }

    /* ========== FLASHLOAN CALLBACK ========== */
    // For stoploss. This function is delegateCalled by Vault.
    function receiveFlashLoan(
        IERC20[] memory _tokens,
        uint256[] memory _amounts,
        uint256[] memory,
        bytes memory _userData
    ) external {
        uint8 _flashloanType = abi.decode(_userData, (uint8));
        if (_flashloanType == uint8(IOrangeVaultV1.FlashloanType.STOPLOSS)) {
            (, uint256 _amount1, uint256 _amount0) = abi.decode(_userData, (uint8, uint256, uint256));

            // Repay Token1
            ILendingPoolManager(lendingPool).repay(_amount1);
            // Withdraw Token0 as collateral
            ILendingPoolManager(lendingPool).withdraw(_amount0);

            // Swap to repay the flashloaned token
            if (_amounts[0] > 0) {
                (address _tokenAnother, address _tokenFlashLoaned) = (address(_tokens[0]) == address(token0))
                    ? (address(token1), address(token0))
                    : (address(token0), address(token1));

                ISwapRouter(router).swapAmountOut(
                    _tokenAnother,
                    _tokenFlashLoaned,
                    routerFee,
                    _amounts[0] //uncheckable
                );
            }
        }
        //repay flashloan
        IERC20(_tokens[0]).safeTransfer(balancer, _amounts[0]);
    }
}
