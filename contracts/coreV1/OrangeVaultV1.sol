// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeVaultV1} from "../interfaces/IOrangeVaultV1.sol";
import {IOrangeParametersV1} from "../interfaces/IOrangeParametersV1.sol";
import {ILiquidityPoolManager} from "../interfaces/ILiquidityPoolManager.sol";
import {ILendingPoolManager} from "../interfaces/ILendingPoolManager.sol";

//extends
import {OrangeValidationChecker} from "./OrangeValidationChecker.sol";
import {OrangeERC20} from "./OrangeERC20.sol";

//libraries
import {Proxy} from "../libs/Proxy.sol";
import {ErrorsV1} from "./ErrorsV1.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";
import {OracleLibrary} from "../libs/uniswap/OracleLibrary.sol";
import {UniswapRouterSwapper, ISwapRouter} from "../libs/UniswapRouterSwapper.sol";
import {BalancerFlashloan, IBalancerVault, IBalancerFlashLoanRecipient, IERC20} from "../libs/BalancerFlashloan.sol";
import {UniswapV3LiquidityPoolManager} from "../poolManager/UniswapV3LiquidityPoolManager.sol";
import {AaveLendingPoolManager} from "../poolManager/AaveLendingPoolManager.sol";

contract OrangeVaultV1 is IOrangeVaultV1, IBalancerFlashLoanRecipient, OrangeValidationChecker, Proxy {
    using SafeERC20 for IERC20;
    using FullMath for uint256;
    using UniswapRouterSwapper for ISwapRouter;
    using BalancerFlashloan for IBalancerVault;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        address _pool,
        address _aave,
        address _params,
        address _router,
        uint24 _routerFee,
        address _balancer
    ) OrangeERC20(_name, _symbol) {
        // setting adresses and approving
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        //deploy liquidity pool manager
        liquidityPool = address(new UniswapV3LiquidityPoolManager(address(this), _token0, _token1, _pool));
        token0.safeApprove(liquidityPool, type(uint256).max);
        token1.safeApprove(liquidityPool, type(uint256).max);

        //deploy lending pool manager
        lendingPool = address(new AaveLendingPoolManager(address(this), _token0, _token1, _aave));
        token0.safeApprove(lendingPool, type(uint256).max);
        token1.safeApprove(lendingPool, type(uint256).max);

        params = IOrangeParametersV1(_params);

        router = _router;
        token0.safeApprove(_router, type(uint256).max);
        token1.safeApprove(_router, type(uint256).max);
        routerFee = _routerFee;
        balancer = _balancer;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc IOrangeVaultV1
    function convertToShares(uint256 _assets) external view returns (uint256) {
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

    /// @inheritdoc IOrangeVaultV1
    function getUnderlyingBalances() external view returns (UnderlyingAssets memory underlyingAssets) {
        return _getUnderlyingBalances(lowerTick, upperTick);
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    /// @notice internal function of totalAssets
    function _totalAssets(int24 _lowerTick, int24 _upperTick) internal view returns (uint256 totalAssets_) {
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(_lowerTick, _upperTick);
        (uint256 amount0Collateral, uint256 amount1Debt) = ILendingPoolManager(lendingPool).balances();

        uint256 amount0Balance = _underlyingAssets.liquidityAmount0 +
            _underlyingAssets.accruedFees0 +
            _underlyingAssets.vaultAmount0;
        uint256 amount1Balance = _underlyingAssets.liquidityAmount1 +
            _underlyingAssets.accruedFees1 +
            _underlyingAssets.vaultAmount1;
        return _alignTotalAsset(amount0Balance, amount1Balance, amount0Collateral, amount1Debt);
    }

    /// @notice Compute total asset price as Token0
    /// @dev Underlying Assets - debt + supply called by _totalAssets
    function _alignTotalAsset(
        uint256 amount0Balance,
        uint256 amount1Balance,
        uint256 amount0Collateral,
        uint256 amount1Debt
    ) internal view returns (uint256 totalAlignedAssets) {
        if (amount1Balance < amount1Debt) {
            uint256 amount1deducted = amount1Debt - amount1Balance;
            amount1deducted = OracleLibrary.getQuoteAtTick(
                ILiquidityPoolManager(liquidityPool).getCurrentTick(),
                uint128(amount1deducted),
                address(token1),
                address(token0)
            );
            totalAlignedAssets = amount0Balance + amount0Collateral - amount1deducted;
        } else {
            uint256 amount1Added = amount1Balance - amount1Debt;
            if (amount1Added > 0) {
                amount1Added = OracleLibrary.getQuoteAtTick(
                    ILiquidityPoolManager(liquidityPool).getCurrentTick(),
                    uint128(amount1Added),
                    address(token1),
                    address(token0)
                );
            }
            totalAlignedAssets = amount0Balance + amount0Collateral + amount1Added;
        }
    }

    /// @notice Get the amount of underlying assets
    /// The assets includes added liquidity, fees and left amount in this vault
    /// @dev similar to Arrakis'
    function _getUnderlyingBalances(
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (UnderlyingAssets memory underlyingAssets) {
        uint128 liquidity = ILiquidityPoolManager(liquidityPool).getCurrentLiquidity(lowerTick, upperTick);
        // compute current holdings from liquidity
        if (liquidity > 0) {
            (underlyingAssets.liquidityAmount0, underlyingAssets.liquidityAmount1) = ILiquidityPoolManager(
                liquidityPool
            ).getAmountsForLiquidity(_lowerTick, _upperTick, liquidity);
        }

        (underlyingAssets.accruedFees0, underlyingAssets.accruedFees1) = ILiquidityPoolManager(liquidityPool)
            .getFeesEarned(_lowerTick, _upperTick);

        underlyingAssets.vaultAmount0 = token0.balanceOf(address(this));
        underlyingAssets.vaultAmount1 = token1.balanceOf(address(this));
    }

    ///@notice Compute target position by shares
    ///@dev called by deposit and redeem
    function _computeTargetPositionByShares(
        uint256 _collateralAmount0,
        uint256 _debtAmount1,
        uint256 _token0Balance,
        uint256 _token1Balance,
        uint256 _shares,
        uint256 _totalSupply
    ) internal pure returns (Positions memory _position) {
        _position.collateralAmount0 = _collateralAmount0.mulDiv(_shares, _totalSupply);
        _position.debtAmount1 = _debtAmount1.mulDiv(_shares, _totalSupply);
        _position.token0Balance = _token0Balance.mulDiv(_shares, _totalSupply);
        _position.token1Balance = _token1Balance.mulDiv(_shares, _totalSupply);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @inheritdoc IOrangeVaultV1
    function deposit(
        uint256 _shares,
        uint256 _maxAssets,
        bytes32[] calldata _merkleProof
    ) external Allowlisted(_merkleProof) returns (uint256) {
        //validation check
        if (_shares == 0 || _maxAssets == 0) revert(ErrorsV1.INVALID_AMOUNT);

        //Case1: first depositor
        if (totalSupply == 0) {
            if (_maxAssets < params.minDepositAmount()) {
                revert(ErrorsV1.INVALID_DEPOSIT_AMOUNT);
            }
            token0.safeTransferFrom(msg.sender, address(this), _maxAssets);
            uint _initialBurnedBalance = (10 ** decimals() / 1000);
            uint _actualDepositAmount = _maxAssets - _initialBurnedBalance;
            _mint(msg.sender, _actualDepositAmount);
            _mint(address(0), _initialBurnedBalance); // for manipulation resistance
            _checkDepositCap();
            return _actualDepositAmount;
        }

        //Case2: from second depositor.
        //take current positions.
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(lowerTick, upperTick);
        uint128 _liquidity = ILiquidityPoolManager(liquidityPool).getCurrentLiquidity(lowerTick, upperTick);

        //calculate additional Aave position and Contract balances by shares
        Positions memory _additionalPosition = _computeTargetPositionByShares(
            ILendingPoolManager(lendingPool).balanceOfCollateral(),
            ILendingPoolManager(lendingPool).balanceOfDebt(),
            _underlyingAssets.vaultAmount0 + _underlyingAssets.accruedFees0, //including pending fees
            _underlyingAssets.vaultAmount1 + _underlyingAssets.accruedFees1, //including pending fees
            _shares,
            totalSupply
        );

        //calculate additional amounts based on liquidity by shares
        uint128 _additionalLiquidity = SafeCast.toUint128(uint256(_liquidity).mulDiv(_shares, totalSupply));

        //transfer the base token (token0) to this contract
        token0.safeTransferFrom(msg.sender, address(this), _maxAssets);

        //append position
        _depositFlashloan(
            _additionalPosition, //Additional Hedge Position and Token remains in the vault.
            _additionalLiquidity, //Additional Liquidity for AMM.
            _maxAssets //Token0 from User
        );

        // mint share to receiver
        _mint(msg.sender, _shares);
        _checkDepositCap();

        emitAction(ActionType.DEPOSIT);
        return _shares;
    }

    /// @notice flashloan Token0 or 1 from Balancer to construct position smoothly.
    /// @dev Balancer.makeFlashLoan() callbacks receiveFlashLoan()
    function _depositFlashloan(
        Positions memory _additionalPosition,
        uint128 _additionalLiquidity,
        uint256 _maxAssets
    ) internal {
        uint256 _additionalLiquidityAmount0;
        uint256 _additionalLiquidityAmount1;
        if (_additionalLiquidity > 0) {
            (_additionalLiquidityAmount0, _additionalLiquidityAmount1) = ILiquidityPoolManager(liquidityPool)
                .getAmountsForLiquidity(lowerTick, upperTick, _additionalLiquidity);
        }

        //Case1: Overhedge. (Debt Token1 > Liquidity Token1 + Vault Token1)
        if (_additionalPosition.debtAmount1 > _additionalLiquidityAmount1 + _additionalPosition.token1Balance) {
            /**
             * Overhedge
             * Flashloan Token0. append positions. swap Token1=>Token0 (leave some Token1 for _additionalPosition.token1Balance ). Return the loan.
             */
            bytes memory _userData = abi.encode(
                FlashloanType.DEPOSIT_OVERHEDGE,
                _additionalPosition,
                _additionalLiquidity,
                _maxAssets,
                msg.sender
            );
            flashloanHash = keccak256(_userData); //set stroage for callback
            IBalancerVault(balancer).makeFlashLoan(
                IBalancerFlashLoanRecipient(address(this)),
                token0,
                _additionalPosition.collateralAmount0 + _additionalLiquidityAmount0 + 1,
                _userData
            );
        } else {
            /**
             * Underhedge
             * Flashloan Token1. append positions. swap Token0=>Token1 (swap some more Token1 for _additionalPosition.token1Balance). Return the loan.
             */
            bytes memory _userData = abi.encode(
                FlashloanType.DEPOSIT_UNDERHEDGE,
                _additionalPosition,
                _additionalLiquidity,
                _maxAssets,
                msg.sender
            );
            flashloanHash = keccak256(_userData); //set stroage for callback
            IBalancerVault(balancer).makeFlashLoan(
                IBalancerFlashLoanRecipient(address(this)),
                token1,
                _additionalPosition.debtAmount1 > _additionalLiquidityAmount1
                    ? 0
                    : _additionalLiquidityAmount1 - _additionalPosition.debtAmount1 + 1,
                _userData
            );
        }
    }

    /// @inheritdoc IOrangeVaultV1
    function redeem(uint256 _shares, uint256 _minAssets) external returns (uint256 returnAssets_) {
        //validation
        if (_shares == 0) {
            revert(ErrorsV1.INVALID_AMOUNT);
        }

        uint256 _totalSupply = totalSupply;

        //burn
        _burn(msg.sender, _shares);

        // Remove liquidity by shares and collect all fees
        (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) = _redeemLiqidityByShares(
            _shares,
            _totalSupply,
            lowerTick,
            upperTick
        );

        //compute redeem positions except liquidity
        //because liquidity is computed by shares
        //so `token0.balanceOf(address(this)) - _burnedLiquidityAmount0` means remaining balance and colleted fee
        Positions memory _redeemPosition = _computeTargetPositionByShares(
            ILendingPoolManager(lendingPool).balanceOfCollateral(),
            ILendingPoolManager(lendingPool).balanceOfDebt(),
            token0.balanceOf(address(this)) - _burnedLiquidityAmount0,
            token1.balanceOf(address(this)) - _burnedLiquidityAmount1,
            _shares,
            _totalSupply
        );

        // `_redeemableAmount0/1` are currently hold balances in this vault and will transfer to receiver
        uint256 _redeemableAmount0 = _redeemPosition.token0Balance + _burnedLiquidityAmount0;
        uint256 _redeemableAmount1 = _redeemPosition.token1Balance + _burnedLiquidityAmount1;

        uint256 _flashLoanAmount1;
        if (_redeemPosition.debtAmount1 >= _redeemableAmount1) {
            unchecked {
                _flashLoanAmount1 = _redeemPosition.debtAmount1 - _redeemableAmount1;
            }
        } else {
            // swap surplus Token1 to return receiver as Token0
            _redeemableAmount0 += ISwapRouter(router).swapAmountIn(
                address(token1),
                address(token0),
                routerFee,
                _redeemableAmount1 - _redeemPosition.debtAmount1
            );
        }

        // memorize balance of token0 to be remained in vault
        uint256 _unRedeemableBalance0 = token0.balanceOf(address(this)) - _redeemableAmount0;

        // execute flashloan (repay Token1 and withdraw Token0 in callback function `receiveFlashLoan`)
        bytes memory _userData = abi.encode(
            FlashloanType.REDEEM,
            _redeemPosition.debtAmount1,
            _redeemPosition.collateralAmount0
        );
        flashloanHash = keccak256(_userData); //set stroage for callback
        IBalancerVault(balancer).makeFlashLoan(
            IBalancerFlashLoanRecipient(address(this)),
            token1,
            _flashLoanAmount1,
            _userData
        );

        returnAssets_ = token0.balanceOf(address(this)) - _unRedeemableBalance0;

        // check if redemption has done as expected or not
        if (returnAssets_ < _minAssets) {
            revert(ErrorsV1.LESS_AMOUNT);
        }

        // complete redemption
        token0.safeTransfer(msg.sender, returnAssets_);

        emitAction(ActionType.REDEEM);
    }

    ///@notice remove liquidity by share ratio and collect all fees
    ///@dev called by redeem
    function _redeemLiqidityByShares(
        uint256 _shares,
        uint256 _totalSupply,
        int24 _lowerTick,
        int24 _upperTick
    ) internal returns (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) {
        uint128 _liquidity = ILiquidityPoolManager(liquidityPool).getCurrentLiquidity(_lowerTick, _upperTick);
        //unnecessary to check _totalSupply == 0 because an error occurs in redeem before calling this function
        uint128 _burnLiquidity = SafeCast.toUint128(uint256(_liquidity).mulDiv(_shares, _totalSupply));
        (_burnedLiquidityAmount0, _burnedLiquidityAmount1) = ILiquidityPoolManager(liquidityPool).burnAndCollect(
            _lowerTick,
            _upperTick,
            _burnLiquidity
        );
    }

    /// @inheritdoc IOrangeVaultV1
    function emitAction(ActionType _actionType) public {
        (uint256 _amount0Collateral, uint256 _amount1Debt) = ILendingPoolManager(lendingPool).balances();
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingBalances(lowerTick, upperTick);
        uint256 _amount0Balance = _underlyingAssets.liquidityAmount0 +
            _underlyingAssets.accruedFees0 +
            _underlyingAssets.vaultAmount0;
        uint256 _amount1Balance = _underlyingAssets.liquidityAmount1 +
            _underlyingAssets.accruedFees1 +
            _underlyingAssets.vaultAmount1;
        uint256 __totalAssets = _alignTotalAsset(_amount0Balance, _amount1Balance, _amount0Collateral, _amount1Debt);

        emit Action(
            _actionType,
            msg.sender,
            _amount0Collateral,
            _amount1Debt,
            _underlyingAssets.liquidityAmount0,
            _underlyingAssets.liquidityAmount1,
            _underlyingAssets.accruedFees0,
            _underlyingAssets.accruedFees1,
            _underlyingAssets.vaultAmount0,
            _underlyingAssets.vaultAmount1,
            __totalAssets,
            totalSupply
        );
    }

    function _checkDepositCap() internal view {
        if (_totalAssets(lowerTick, upperTick) > params.depositCap()) {
            revert(ErrorsV1.CAPOVER);
        }
    }

    /* ========== EXTERNAL FUNCTIONS (Delegate call) ========== */

    /// @inheritdoc IOrangeVaultV1
    function stoploss(int24) external {
        if (msg.sender != params.helper()) revert(ErrorsV1.ONLY_HELPER);

        _delegate(params.strategyImpl());
    }

    /// @inheritdoc IOrangeVaultV1
    function rebalance(int24, int24, Positions memory, uint128) external {
        if (msg.sender != params.helper()) revert(ErrorsV1.ONLY_HELPER);

        _delegate(params.strategyImpl());
    }

    /* ========== FLASHLOAN CALLBACK ========== */
    ///@notice There are two types of _userData, determined by the FlashloanType (REDEEM or DEPOSIT_OVERHEDGE/UNDERHEDGE).
    function receiveFlashLoan(
        IERC20[] memory _tokens,
        uint256[] memory _amounts,
        uint256[] memory,
        bytes memory _userData
    ) external {
        if (msg.sender != balancer) revert(ErrorsV1.ONLY_BALANCER_VAULT);
        //check validity
        if (flashloanHash == bytes32(0) || flashloanHash != keccak256(_userData))
            revert(ErrorsV1.INVALID_FLASHLOAN_HASH);
        flashloanHash = bytes32(0); //clear cache

        uint8 _flashloanType = abi.decode(_userData, (uint8));

        if (
            _flashloanType == uint8(FlashloanType.DEPOSIT_OVERHEDGE) ||
            _flashloanType == uint8(FlashloanType.DEPOSIT_UNDERHEDGE)
        ) {
            _depositInFlashloan(_flashloanType, _amounts[0], _userData);
        } else if (_flashloanType == uint8(FlashloanType.REDEEM)) {
            (, uint256 _amount1, uint256 _amount0) = abi.decode(_userData, (uint8, uint256, uint256)); // (, debt, collateral)

            // repay debt
            ILendingPoolManager(lendingPool).repay(_amount1);

            // withdraw collateral
            ILendingPoolManager(lendingPool).withdraw(_amount0);

            //swap to repay flashloan
            if (_amounts[0] > 0) {
                (address _tokenAnother, address _tokenFlashLoaned) = (address(_tokens[0]) == address(token0))
                    ? (address(token1), address(token0))
                    : (address(token0), address(token1));
                // Swap to repay the flashloaned token
                ISwapRouter(router).swapAmountOut(
                    _tokenAnother, //In
                    _tokenFlashLoaned, //Out
                    routerFee,
                    _amounts[0]
                );
            }
        } else {
            //delegate call
            _delegate(params.strategyImpl());
        }

        //repay flashloan
        IERC20(_tokens[0]).safeTransfer(balancer, _amounts[0]);
    }

    function _depositInFlashloan(uint8 _flashloanType, uint256 flashloanAmount, bytes memory _userData) internal {
        (, Positions memory _positions, uint128 _additionalLiquidity, uint256 _maxAssets, address _receiver) = abi
            .decode(_userData, (uint8, Positions, uint128, uint256, address));
        /**
         * appending positions
         * 1. collateral Token0
         * 2. borrow Token1
         * 3. liquidity Token0
         * 4. liquidity Token1
         * 5. additional Token0 (in the Vault)
         * 6. additional Token1 (in the Vault)
         */

        //Supply Token0 and Borrow Token1 (#1 and #2)
        ILendingPoolManager(lendingPool).supply(_positions.collateralAmount0);
        ILendingPoolManager(lendingPool).borrow(_positions.debtAmount1);

        //Add Liquidity (#3 and #4)
        uint256 _additionalLiquidityAmount0;
        uint256 _additionalLiquidityAmount1;
        if (_additionalLiquidity > 0) {
            (_additionalLiquidityAmount0, _additionalLiquidityAmount1) = ILiquidityPoolManager(liquidityPool).mint(
                lowerTick,
                upperTick,
                _additionalLiquidity
            );
        }

        uint256 _actualUsedAmount0;
        if (_flashloanType == uint8(FlashloanType.DEPOSIT_OVERHEDGE)) {
            // Token0 is flashLoaned.
            // Calculate the amount of surplus Token1 and swap for Token0 (Leave some Token1 to achieve #5)
            uint256 _surplusAmount1 = _positions.debtAmount1 - (_additionalLiquidityAmount1 + _positions.token1Balance);
            uint256 _amountOutFromSurplusToken1Sale = ISwapRouter(router).swapAmountIn(
                address(token1), //In
                address(token0), //Out
                routerFee,
                _surplusAmount1
            );

            _actualUsedAmount0 = flashloanAmount + _positions.token0Balance - _amountOutFromSurplusToken1Sale;
        } else if (_flashloanType == uint8(FlashloanType.DEPOSIT_UNDERHEDGE)) {
            // Token1 is flashLoaned.
            // Calculate the amount of Token1 needed to be swapped to repay the loan, then swap Token0=>Token1 (Swap more Token0 for Token1 to achieve #5)
            uint256 amount1ToBeSwapped = _additionalLiquidityAmount1 +
                _positions.token1Balance -
                _positions.debtAmount1;
            uint256 amount0UsedForToken1 = ISwapRouter(router).swapAmountOut(
                address(token0), //In
                address(token1), //Out
                routerFee,
                amount1ToBeSwapped
            );

            _actualUsedAmount0 =
                _positions.collateralAmount0 +
                _additionalLiquidityAmount0 +
                _positions.token0Balance +
                amount0UsedForToken1;
        }

        //Refund the unspent Token0 (Leave some Token0 for #6)
        if (_maxAssets < _actualUsedAmount0) revert(ErrorsV1.LESS_MAX_ASSETS);
        unchecked {
            uint256 _refundAmount0 = _maxAssets - _actualUsedAmount0;
            if (_refundAmount0 > 0) token0.safeTransfer(_receiver, _refundAmount0);
        }
    }
}
