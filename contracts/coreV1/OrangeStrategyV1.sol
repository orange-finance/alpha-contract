// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeV1Parameters} from "../interfaces/IOrangeV1Parameters.sol";
import {IOrangeVaultV1} from "../interfaces/IOrangeVaultV1.sol";
import {IUniswapV3LiquidityPoolManager} from "../interfaces/IUniswapV3LiquidityPoolManager.sol";
import {IAaveLendingPoolManager} from "../interfaces/IAaveLendingPoolManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
//libraries
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../libs/uniswap/OracleLibrary.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IFlashLoanRecipient, IERC20} from "../interfaces/IFlashLoanRecipient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract OrangeStrategyV1 {
    using FullMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    /* ========== STORAGES ========== */
    bool public hasPosition;
    bytes32 flashloanHash; //tempolary use in flashloan

    /* ========== PARAMETERS ========== */
    IOrangeVaultV1 public vault;
    IUniswapV3LiquidityPoolManager public liquidityPool;
    IAaveLendingPoolManager public lendingPool;
    IERC20 public token0; //collateral and deposited currency by users
    IERC20 public token1; //debt and hedge target token
    IOrangeV1Parameters public params;

    /* ========== MODIFIER ========== */

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault) {
        // setting adresses and approving
        vault = IOrangeVaultV1(_vault);
        token0 = vault.token0();
        token1 = vault.token1();
        liquidityPool = vault.liquidityPool();
        lendingPool = vault.lendingPool();
        params = IOrangeV1Parameters(vault.params());
    }

    ///@notice Check slippage by tick
    function _checkTickSlippage(int24 _currentTick, int24 _inputTick) internal view {
        if (
            _currentTick > _inputTick + int24(params.tickSlippageBPS()) ||
            _currentTick < _inputTick - int24(params.tickSlippageBPS())
        ) {
            revert("Errors.HIGH_SLIPPAGE");
        }
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function stoploss(int24 _inputTick) external {
        if (!params.strategists(msg.sender) && params.gelatoExecutor() != msg.sender) {
            revert("Errors.ONLY_STRATEGISTS_OR_GELATO");
        }

        if (IERC20(address(vault)).totalSupply() == 0) return;

        _checkTickSlippage(liquidityPool.getCurrentTick(), _inputTick);

        // 1. Remove liquidity
        // 2. Collect fees
        uint128 liquidity = liquidityPool.getCurrentLiquidity(vault.lowerTick(), vault.upperTick());
        if (liquidity > 0) {
            _burnAndCollectFees(vault.lowerTick(), vault.upperTick(), liquidity);
        }

        uint256 _repayingDebt = lendingPool.balanceOfDebt();
        uint256 _balanceToken1 = token1.balanceOf(address(vault));
        uint256 _withdrawingCollateral = lendingPool.balanceOfCollateral();

        // Flashloan to borrow Repay Token1
        uint256 _flashBorrowToken1;
        if (_repayingDebt > _balanceToken1) {
            unchecked {
                _flashBorrowToken1 = _repayingDebt - _balanceToken1;
            }
        }

        // execute flashloan (repay Token1 and withdraw Token0 in callback function `receiveFlashLoan`)
        _makeFlashLoan(
            token1,
            _flashBorrowToken1,
            abi.encode(IOrangeVaultV1.FlashloanType.STOPLOSS, _repayingDebt, _withdrawingCollateral)
        );

        // swap remaining all Token1 to Token0
        _balanceToken1 = token1.balanceOf(address(vault));
        if (_balanceToken1 > 0) {
            _swapAmountIn(true, _balanceToken1);
        }

        hasPosition = false;
    }

    function rebalance(
        int24 _currentLowerTick,
        int24 _currentUpperTick,
        int24 _newLowerTick,
        int24 _newUpperTick,
        IOrangeVaultV1.Positions memory _targetPosition,
        uint128 _minNewLiquidity
    ) external {
        if (!params.strategists(msg.sender)) {
            revert("Errors.ONLY_STRATEGISTS");
        }
        //validation of tickSpacing
        liquidityPool.validateTicks(_newLowerTick, _newUpperTick);

        // 1. burn and collect fees
        uint128 _liquidity = liquidityPool.getCurrentLiquidity(_currentLowerTick, _currentUpperTick);
        _burnAndCollectFees(_currentLowerTick, _currentUpperTick, _liquidity);

        if (IERC20(address(vault)).totalSupply() == 0) {
            return;
        }

        // 2. get current position
        IOrangeVaultV1.Positions memory _currentPosition = IOrangeVaultV1.Positions(
            lendingPool.balanceOfCollateral(),
            lendingPool.balanceOfDebt(),
            token0.balanceOf(address(vault)),
            token1.balanceOf(address(vault))
        );

        // 4. execute hedge
        _executeHedgeRebalance(_currentPosition, _targetPosition);

        // 5. Add liquidity
        uint128 _targetLiquidity = _addLiquidityInRebalance(
            _newLowerTick,
            _newUpperTick,
            _targetPosition.token0Balance, // amount of token0 to be added to Uniswap
            _targetPosition.token1Balance // amount of token1 to be added to Uniswap
        );
        if (_targetLiquidity < _minNewLiquidity) {
            revert("Errors.LESS_LIQUIDITY");
        }

        if (_targetLiquidity > 0) {
            hasPosition = true;
        }
    }

    /* ========== WRITE FUNCTIONS(INTERNAL) ========== */
    ///@notice make parameters and execute Flashloan
    function _makeFlashLoan(IERC20 _token, uint256 _amount, bytes memory _userData) internal {
        IERC20[] memory _tokensFlashloan = new IERC20[](1);
        _tokensFlashloan[0] = _token;
        uint256[] memory _amountsFlashloan = new uint256[](1);
        _amountsFlashloan[0] = _amount;
        flashloanHash = keccak256(_userData); //set stroage for callback
        IVault(params.balancer()).flashLoan(
            IFlashLoanRecipient(address(vault)),
            _tokensFlashloan,
            _amountsFlashloan,
            _userData
        );
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

    ///@notice Swap exact amount out
    function _swapAmountOut(bool _zeroForOne, uint256 _amountOut) internal returns (uint256 amountIn_) {
        if (_amountOut == 0) return 0;
        (address tokenIn, address tokenOut) = (_zeroForOne)
            ? (address(token0), address(token1))
            : (address(token1), address(token0));
        ISwapRouter.ExactOutputSingleParams memory _params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: params.routerFee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: _amountOut,
            amountInMaximum: type(uint256).max,
            sqrtPriceLimitX96: 0
        });
        amountIn_ = ISwapRouter(params.router()).exactOutputSingle(_params);
    }

    ///@notice Swap exact amount in
    function _swapAmountIn(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        if (_amountIn == 0) return 0;
        (address tokenIn, address tokenOut) = (_zeroForOne)
            ? (address(token0), address(token1))
            : (address(token1), address(token0));
        ISwapRouter.ExactInputSingleParams memory _params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: params.routerFee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        amountOut_ = ISwapRouter(params.router()).exactInputSingle(_params);
    }

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
                    if (_repay > _currentPosition.token1Balance) {
                        _swapAmountOut(
                            false,
                            _repay - _currentPosition.token1Balance //uncheckable
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
        uint256 _balance0 = token0.balanceOf(address(vault));
        uint256 _balance1 = token1.balanceOf(address(vault));

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

    /* ========== FLASHLOAN CALLBACK ========== */
    function receiveFlashLoan(
        IERC20[] memory _tokens,
        uint256[] memory _amounts,
        uint256[] memory,
        bytes memory _userData
    ) external {
        if (msg.sender != params.balancer()) revert("Errors.ONLY_BALANCER_VAULT");

        uint8 _flashloanType = abi.decode(_userData, (uint8));
        if (_flashloanType == uint8(IOrangeVaultV1.FlashloanType.STOPLOSS)) {
            //hash check
            if (flashloanHash == bytes32(0) || flashloanHash != keccak256(_userData))
                revert("Errors.INVALID_FLASHLOAN_HASH");
            flashloanHash = bytes32(0); //clear storage

            (, uint256 _amount1, uint256 _amount0) = abi.decode(_userData, (uint8, uint256, uint256));

            // Repay Token1
            lendingPool.repay(_amount1);
            // Withdraw Token0 as collateral
            lendingPool.withdraw(_amount0);

            //swap to repay flashloan
            if (_amounts[0] > 0) {
                bool _zeroForOne = (address(_tokens[0]) == address(token0)) ? false : true;
                // swap Token0 to Token1 to repay flashloan
                _swapAmountOut(_zeroForOne, _amounts[0]);
            }
        }
        //repay flashloan
        IERC20(_tokens[0]).safeTransfer(params.balancer(), _amounts[0]);
    }

    /* ========== VIEW FUNCTIONS ========== */

    //TODO move to computer
    // function getRebalancedLiquidity(
    //     int24 _newLowerTick,
    //     int24 _newUpperTick,
    //     int24 _newStoplossUpperTick,
    //     uint256 _hedgeRatio
    // ) external view returns (uint128 liquidity_) {
    //     uint256 _assets = vault.totalAssets();
    //     uint256 _ltv = _getLtvByRange(_newStoplossUpperTick);
    //     IOrangeVaultV1.Positions memory _position = _computeRebalancePosition(
    //         _assets,
    //         _newLowerTick,
    //         _newUpperTick,
    //         _ltv,
    //         _hedgeRatio
    //     );

    //     //compute liquidity
    //     liquidity_ = liquidityPool.getLiquidityForAmounts(
    //         _newLowerTick,
    //         _newUpperTick,
    //         _position.token0Balance,
    //         _position.token1Balance
    //     );
    // }

    //TODO move to computer
    // function computeRebalancePosition(
    //     uint256 _assets0,
    //     int24 _lowerTick,
    //     int24 _upperTick,
    //     uint256 _ltv,
    //     uint256 _hedgeRatio
    // ) external view returns (IOrangeVaultV1.Positions memory position_) {
    //     position_ = _computeRebalancePosition(_assets0, _lowerTick, _upperTick, _ltv, _hedgeRatio);
    // }

    //TODO move to computer
    // function getLtvByRange(int24 _upperTick) external view returns (uint256 ltv_) {
    //     ltv_ = _getLtvByRange(_upperTick);
    // }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    //TODO move to computer
    // function _quoteAtTick(
    //     int24 _tick,
    //     uint128 baseAmount,
    //     address baseToken,
    //     address quoteToken
    // ) internal pure returns (uint256) {
    //     return OracleLibrary.getQuoteAtTick(_tick, baseAmount, baseToken, quoteToken);
    // }

    //TODO move to computer
    // function _quoteCurrent(uint128 baseAmount, address baseToken, address quoteToken) internal view returns (uint256) {
    //     (, int24 _tick, , , , , ) = liquidityPool.pool().slot0();
    //     return _quoteAtTick(_tick, baseAmount, baseToken, quoteToken);
    // }

    //TODO move to computer
    /// @notice Compute the amount of collateral/debt and token0/token1 to Liquidity
    // function _computeRebalancePosition(
    //     uint256 _assets0,
    //     int24 _lowerTick,
    //     int24 _upperTick,
    //     uint256 _ltv,
    //     uint256 _hedgeRatio
    // ) internal view returns (IOrangeVaultV1.Positions memory position_) {
    //     if (_assets0 == 0) return IOrangeVaultV1.Positions(0, 0, 0, 0);

    //     // compute ETH/USDC amount ration to add liquidity
    //     (uint256 _amount0, uint256 _amount1) = liquidityPool.getAmountsForLiquidity(
    //         _lowerTick,
    //         _upperTick,
    //         1e18 //any amount
    //     );
    //     uint256 _amount1ValueInToken0 = _quoteCurrent(uint128(_amount1), address(token1), address(token0));

    //     if (_hedgeRatio == 0) {
    //         position_.token1Balance = (_amount1ValueInToken0 + _amount0 == 0)
    //             ? 0
    //             : _assets0.mulDiv(_amount0, (_amount1ValueInToken0 + _amount0));
    //         position_.token1Balance = (_amount0 == 0) ? 0 : position_.token0Balance.mulDiv(_amount1, _amount0);
    //     } else {
    //         //compute collateral/asset ratio
    //         uint256 _x = (_amount1ValueInToken0 == 0) ? 0 : MAGIC_SCALE_1E8.mulDiv(_amount0, _amount1ValueInToken0);
    //         uint256 _collateralRatioReciprocal = MAGIC_SCALE_1E8 -
    //             _ltv +
    //             MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio) +
    //             MAGIC_SCALE_1E8.mulDiv(_ltv, _hedgeRatio).mulDiv(_x, MAGIC_SCALE_1E8);

    //         //Collateral
    //         position_.collateralAmount0 = (_collateralRatioReciprocal == 0)
    //             ? 0
    //             : _assets0.mulDiv(MAGIC_SCALE_1E8, _collateralRatioReciprocal);

    //         uint256 _borrow0 = position_.collateralAmount0.mulDiv(_ltv, MAGIC_SCALE_1E8);
    //         //borrowing usdc amount to weth
    //         position_.debtAmount1 = _quoteCurrent(uint128(_borrow0), address(token0), address(token1));

    //         // amount added on Uniswap
    //         position_.token1Balance = position_.debtAmount1.mulDiv(MAGIC_SCALE_1E8, _hedgeRatio);
    //         position_.token0Balance = (_amount1 == 0) ? 0 : position_.token1Balance.mulDiv(_amount0, _amount1);
    //     }
    // }

    //TODO move to computer
    ///@notice Get LTV by current and range prices
    ///@dev called by _computeRebalancePosition. maxLtv * (current price / upper price)
    // function _getLtvByRange(int24 _upperTick) internal view returns (uint256 ltv_) {
    //     // any amount is right because we only need the ratio
    //     uint256 _currentPrice = _quoteCurrent(1 ether, address(token0), address(token1));
    //     uint256 _upperPrice = _quoteAtTick(_upperTick, 1 ether, address(token0), address(token1));
    //     ltv_ = params.maxLtv();
    //     if (_currentPrice < _upperPrice) {
    //         ltv_ = ltv_.mulDiv(_currentPrice, _upperPrice);
    //     }
    // }
}
