// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeV1Parameters} from "../interfaces/IOrangeV1Parameters.sol";
import {IOrangeVaultV1} from "../interfaces/IOrangeVaultV1.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";
import {ILendingPoolManager} from "../interfaces/ILendingPoolManager.sol";

//libraries
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UniswapRouterSwapper, ISwapRouter} from "../libs/UniswapRouterSwapper.sol";
import {BalancerFlashloan, IBalancerVault, IBalancerFlashLoanRecipient, IERC20} from "../libs/BalancerFlashloan.sol";

import "forge-std/console2.sol";

contract OrangeStrategyImplV1 {
    using SafeERC20 for IERC20;
    using UniswapRouterSwapper for ISwapRouter;
    using BalancerFlashloan for IBalancerVault;

    /* ========== EXTERNAL FUNCTIONS ========== */
    function rebalance(
        int24 _currentLowerTick,
        int24 _currentUpperTick,
        int24 _newLowerTick,
        int24 _newUpperTick,
        IOrangeVaultV1.Positions memory _targetPosition,
        uint128 _minNewLiquidity
    ) external {
        if (!IOrangeVaultV1(address(this)).params().strategists(msg.sender)) {
            revert("Errors.ONLY_STRATEGISTS");
        }

        //validation of tickSpacing
        ILiquidityPoolManager(IOrangeVaultV1(address(this)).liquidityPool()).validateTicks(
            _newLowerTick,
            _newUpperTick
        );

        // 1. burn and collect fees
        uint128 _liquidity = ILiquidityPoolManager(IOrangeVaultV1(address(this)).liquidityPool()).getCurrentLiquidity(
            _currentLowerTick,
            _currentUpperTick
        );
        ILiquidityPoolManager(IOrangeVaultV1(address(this)).liquidityPool()).burnAndCollect(
            _currentLowerTick,
            _currentUpperTick,
            _liquidity
        );

        if (IERC20(address(this)).totalSupply() == 0) {
            return;
        }

        // 2. get current position
        IOrangeVaultV1.Positions memory _currentPosition = IOrangeVaultV1.Positions(
            ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).balanceOfCollateral(),
            ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).balanceOfDebt(),
            IOrangeVaultV1(address(this)).token0().balanceOf(address(this)),
            IOrangeVaultV1(address(this)).token1().balanceOf(address(this))
        );

        // 4. execute hedge
        _executeHedgeRebalance(_currentPosition, _targetPosition);

        // 5. Add liquidity
        uint128 _targetLiquidity = _addLiquidityInRebalance(
            _newLowerTick,
            _newUpperTick,
            _targetPosition.token0Balance, // amount of token0 to be added to Uniswap
            _targetPosition.token1Balance // amount of IOrangeVaultV1(address(this)).token1() to be added to Uniswap
        );
        if (_targetLiquidity < _minNewLiquidity) {
            revert("Errors.LESS_LIQUIDITY");
        }

        // emit event
        IOrangeVaultV1(address(this)).emitAction(IOrangeVaultV1.ActionType.REBALANCE, msg.sender);
    }

    function stoploss(int24) external {
        // 1. Remove liquidity
        // 2. Collect fees
        uint128 liquidity = ILiquidityPoolManager(IOrangeVaultV1(address(this)).liquidityPool()).getCurrentLiquidity(
            IOrangeVaultV1(address(this)).lowerTick(),
            IOrangeVaultV1(address(this)).upperTick()
        );
        if (liquidity > 0) {
            ILiquidityPoolManager(IOrangeVaultV1(address(this)).liquidityPool()).burnAndCollect(
                IOrangeVaultV1(address(this)).lowerTick(),
                IOrangeVaultV1(address(this)).upperTick(),
                liquidity
            );
        }

        uint256 _repayingDebt = ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).balanceOfDebt();
        uint256 _balanceToken1 = IOrangeVaultV1(address(this)).token1().balanceOf(address(this));
        uint256 _withdrawingCollateral = ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool())
            .balanceOfCollateral();

        // Flashloan to borrow Repay Token1
        uint256 _flashBorrowToken1;
        if (_repayingDebt > _balanceToken1) {
            unchecked {
                _flashBorrowToken1 = _repayingDebt - _balanceToken1;
            }
        }

        // execute flashloan (repay Token1 and withdraw Token0 in callback function `receiveFlashLoan`)
        bytes memory _userData = abi.encode(
            IOrangeVaultV1.FlashloanType.STOPLOSS,
            _repayingDebt,
            _withdrawingCollateral
        );
        IBalancerVault(IOrangeVaultV1(address(this)).params().balancer()).makeFlashLoan(
            IBalancerFlashLoanRecipient(address(this)),
            IOrangeVaultV1(address(this)).token1(),
            _flashBorrowToken1,
            _userData
        );

        // swap remaining all Token1 to Token0
        _balanceToken1 = IOrangeVaultV1(address(this)).token1().balanceOf(address(this));
        if (_balanceToken1 > 0) {
            ISwapRouter(IOrangeVaultV1(address(this)).params().router()).swapAmountIn(
                address(IOrangeVaultV1(address(this)).token0()),
                address(IOrangeVaultV1(address(this)).token1()),
                IOrangeVaultV1(address(this)).params().routerFee(),
                _balanceToken1
            );
        }

        // emit event
        IOrangeVaultV1(address(this)).emitAction(IOrangeVaultV1.ActionType.STOPLOSS, msg.sender);
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */

    /// @notice execute hedge by changing collateral or debt amount
    /// @dev called by rebalance
    function _executeHedgeRebalance(
        IOrangeVaultV1.Positions memory _currentPosition,
        IOrangeVaultV1.Positions memory _targetPosition
    ) internal {
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
            revert("Errors.EQUAL_COLLATERAL_OR_DEBT");
        }
        unchecked {
            if (
                _currentPosition.collateralAmount0 < _targetPosition.collateralAmount0 &&
                _currentPosition.debtAmount1 < _targetPosition.debtAmount1
            ) {
                // case1 supply and borrow
                console2.log("case1 supply and borrow");
                uint256 _supply0 = _targetPosition.collateralAmount0 - _currentPosition.collateralAmount0; //uncheckable
                if (_supply0 > _currentPosition.token0Balance) {
                    // swap (if necessary)
                    ISwapRouter(IOrangeVaultV1(address(this)).params().router()).swapAmountOut(
                        address(IOrangeVaultV1(address(this)).token1()),
                        address(IOrangeVaultV1(address(this)).token0()),
                        IOrangeVaultV1(address(this)).params().routerFee(),
                        _supply0 - _currentPosition.token0Balance //uncheckable
                    );
                }
                ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).supply(_supply0);

                // borrow
                uint256 _borrow1 = _targetPosition.debtAmount1 - _currentPosition.debtAmount1; //uncheckable
                ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).borrow(_borrow1);
            } else {
                if (_currentPosition.debtAmount1 > _targetPosition.debtAmount1) {
                    // case2 repay
                    console2.log("case2 repay");
                    uint256 _repay1 = _currentPosition.debtAmount1 - _targetPosition.debtAmount1; //uncheckable

                    // swap (if necessary)
                    if (_repay1 > _currentPosition.token1Balance) {
                        ISwapRouter(IOrangeVaultV1(address(this)).params().router()).swapAmountOut(
                            address(IOrangeVaultV1(address(this)).token0()),
                            address(IOrangeVaultV1(address(this)).token1()),
                            IOrangeVaultV1(address(this)).params().routerFee(),
                            _repay1 - _currentPosition.token1Balance //uncheckable
                        );
                    }
                    ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).repay(_repay1);

                    if (_currentPosition.collateralAmount0 < _targetPosition.collateralAmount0) {
                        // case2_1 repay and supply
                        console2.log("case2_1 repay and supply");

                        uint256 _supply0 = _targetPosition.collateralAmount0 - _currentPosition.collateralAmount0; //uncheckable
                        ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).supply(_supply0);
                    } else {
                        // case2_2 repay and withdraw
                        console2.log("case2_2 repay and withdraw");
                        uint256 _withdraw0 = _currentPosition.collateralAmount0 - _targetPosition.collateralAmount0; //uncheckable. //possibly, equal
                        ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).withdraw(_withdraw0);
                    }
                } else {
                    // case3 borrow and withdraw
                    console2.log("case3 borrow and withdraw");
                    uint256 _borrow1 = _targetPosition.debtAmount1 - _currentPosition.debtAmount1; //uncheckable. //possibly, equal
                    ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).borrow(_borrow1);
                    // withdraw should be the only option here.
                    uint256 _withdraw0 = _currentPosition.collateralAmount0 - _targetPosition.collateralAmount0; //should be uncheckable. //possibly, equal
                    ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).withdraw(_withdraw0);
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
        uint256 _balance0 = IOrangeVaultV1(address(this)).token0().balanceOf(address(this));
        uint256 _balance1 = IOrangeVaultV1(address(this)).token1().balanceOf(address(this));

        //swap surplus amount
        if (_balance0 >= _targetAmount0 && _balance1 >= _targetAmount1) {
            //no need to swap
        } else {
            unchecked {
                if (_balance0 > _targetAmount0) {
                    ISwapRouter(IOrangeVaultV1(address(this)).params().router()).swapAmountIn(
                        address(IOrangeVaultV1(address(this)).token0()),
                        address(IOrangeVaultV1(address(this)).token1()),
                        IOrangeVaultV1(address(this)).params().routerFee(),
                        _balance0 - _targetAmount0
                    );
                } else if (_balance1 > _targetAmount1) {
                    ISwapRouter(IOrangeVaultV1(address(this)).params().router()).swapAmountIn(
                        address(IOrangeVaultV1(address(this)).token1()),
                        address(IOrangeVaultV1(address(this)).token0()),
                        IOrangeVaultV1(address(this)).params().routerFee(),
                        _balance1 - _targetAmount1
                    );
                }
            }
        }

        targetLiquidity_ = ILiquidityPoolManager(IOrangeVaultV1(address(this)).liquidityPool()).getLiquidityForAmounts(
            _lowerTick,
            _upperTick,
            IOrangeVaultV1(address(this)).token0().balanceOf(address(this)),
            IOrangeVaultV1(address(this)).token1().balanceOf(address(this))
        );
        ILiquidityPoolManager(IOrangeVaultV1(address(this)).liquidityPool()).mint(
            _lowerTick,
            _upperTick,
            targetLiquidity_
        );
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
            ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).repay(_amount1);
            // Withdraw Token0 as collateral
            ILendingPoolManager(IOrangeVaultV1(address(this)).lendingPool()).withdraw(_amount0);

            //swap to repay flashloan
            if (_amounts[0] > 0) {
                (address _tokenIn, address _tokenOut) = (address(_tokens[0]) ==
                    address(IOrangeVaultV1(address(this)).token0()))
                    ? (address(IOrangeVaultV1(address(this)).token1()), address(IOrangeVaultV1(address(this)).token0()))
                    : (
                        address(IOrangeVaultV1(address(this)).token0()),
                        address(IOrangeVaultV1(address(this)).token1())
                    );

                // swap Token0 to Token1 to repay flashloan
                ISwapRouter(IOrangeVaultV1(address(this)).params().router()).swapAmountOut(
                    _tokenIn,
                    _tokenOut,
                    IOrangeVaultV1(address(this)).params().routerFee(),
                    _amounts[0] //uncheckable
                );
            }
        }
        //repay flashloan
        IERC20(_tokens[0]).safeTransfer(IOrangeVaultV1(address(this)).params().balancer(), _amounts[0]);
    }
}
