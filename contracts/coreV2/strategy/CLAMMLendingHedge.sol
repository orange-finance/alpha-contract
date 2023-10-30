// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BaseStrategy} from "@src/coreV2/strategy/BaseStrategy.sol";
import {ICLAMMHelper} from "@src/coreV2/strategy/helper/clamm/ICLAMMHelper.sol";
import {ILendingHelper} from "@src/coreV2/strategy/helper/lending/ILendingHelper.sol";
import {BalancerFlashloan, IBalancerVault, IBalancerFlashLoanRecipient} from "@src/libs/BalancerFlashloan.sol";
import {UniswapRouterSwapper, ISwapRouter} from "@src/libs/UniswapRouterSwapper.sol";

contract CLAMMLendingHedge is BaseStrategy {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using BalancerFlashloan for IBalancerVault;
    using UniswapRouterSwapper for ISwapRouter;

    enum FlashloanType {
        DEPOSIT_OVERHEDGE,
        DEPOSIT_UNDERHEDGE,
        REDEEM,
        STOPLOSS
    }

    struct Positions {
        uint256 collateralAmount0; //collateral amount of token1 on Lending
        uint256 debtAmount1; //debt amount of token0 on Lending
        uint256 token0Balance; //balance of token0
        uint256 token1Balance; //balance of token1
    }

    struct UnderlyingAssets {
        uint256 liquidityAmount0; //liquidity amount of token0 on Uniswap
        uint256 liquidityAmount1; //liquidity amount of token1 on Uniswap
        uint256 accruedFees0; //fees of token0 on Uniswap
        uint256 accruedFees1; //fees of token1 on Uniswap
        uint256 vaultAmount0; //balance of token0 in the vault
        uint256 vaultAmount1; //balance of token1 in the vault
    }

    ICLAMMHelper public immutable clammHelper;
    ILendingHelper public immutable lendingHelper;
    address public immutable clammPool;
    address public immutable lendingPool;
    address public immutable balancer;
    address public immutable router;
    uint24 public immutable routerFee;

    IERC20 immutable token0;
    IERC20 immutable token1;

    bytes32 public flashloanHash;
    int24 public lowerTick;
    int24 public upperTick;

    error OnlyBalancerVault();
    error InvalidFlashloanHash();
    error TooMuchTokenUsed();

    constructor(
        IERC20 token0_,
        IERC20 token1_,
        address tokenizedStrategyImpl,
        ICLAMMHelper clammHelper_,
        address clammPool_,
        ILendingHelper lendingHelper_,
        address lendingPool_,
        address balancer_,
        address router_,
        uint24 routerFee_
    ) BaseStrategy(tokenizedStrategyImpl) {
        token0 = token0_;
        token1 = token1_;
        clammHelper = clammHelper_;
        clammPool = clammPool_;
        lendingHelper = lendingHelper_;
        lendingPool = lendingPool_;
        balancer = balancer_;
        router = router_;
        routerFee = routerFee_;
    }

    function totalAssets() public view override returns (uint256) {}

    /*//////////////////////////////////////////////////////////////
                        Strategy Functions
    //////////////////////////////////////////////////////////////*/

    function _depositCallback(uint256 assets, bytes calldata) internal override {
        //take current positions.
        UnderlyingAssets memory _underlyingAssets = _getUnderlyingAssets(lowerTick, upperTick);

        uint256 _totalAssets = totalAssets();

        uint256 _collateralAmount0 = ILendingHelper(lendingHelper).balanceOfCollateral(lendingPool, address(token0));
        uint256 _debtAmount1 = ILendingHelper(lendingHelper).balanceOfDebt(lendingPool, address(token1));
        uint256 _token0Balance = _underlyingAssets.vaultAmount0 + _underlyingAssets.accruedFees0; //including pending fees
        uint256 _token1Balance = _underlyingAssets.vaultAmount1 + _underlyingAssets.accruedFees1; //including pending fees

        //calculate additional Aave position and Contract balances by assets
        Positions memory _additionalPosition = Positions({
            collateralAmount0: _collateralAmount0.mulDiv(assets, _totalAssets),
            debtAmount1: _debtAmount1.mulDiv(assets, _totalAssets),
            token0Balance: _token0Balance.mulDiv(assets, _totalAssets), //including pending fees
            token1Balance: _token1Balance.mulDiv(assets, _totalAssets) //including pending fees
        });

        uint128 _liquidity = ICLAMMHelper(clammHelper).getCurrentLiquidity(clammPool, lowerTick, upperTick);

        //calculate additional amounts based on liquidity by shares
        uint128 _additionalLiquidity = SafeCast.toUint128(uint256(_liquidity).mulDiv(assets, _totalAssets));
        (uint256 _additionalLiquidityAmount0, uint256 _additionalLiquidityAmount1) = ICLAMMHelper(clammHelper)
            .getAmountsForLiquidity(clammPool, lowerTick, upperTick, _additionalLiquidity);

        bool _overhedge = _additionalPosition.debtAmount1 > _additionalLiquidity + _additionalPosition.token1Balance;

        if (_overhedge) {
            /**
             * Overhedge
             * Flashloan Token0. append positions. swap Token1=>Token0 (leave some Token1 for _additionalPosition.token1Balance ). Return the loan.
             */
            _triggerFlashloanForOverhedge(
                _additionalPosition, //Additional Hedge Position and Token remains in the vault.
                _additionalLiquidity, //Additional Liquidity for AMM.
                _additionalLiquidityAmount0, //Token0 from AMM
                assets //Token0 from User
            );
        } else {
            /**
             * Underhedge
             * Flashloan Token1. append positions. swap Token0=>Token1 (swap some more Token1 for _additionalPosition.token1Balance). Return the loan.
             */
            _triggerFlashloanForUnderhedge(
                _additionalPosition, //Additional Hedge Position and Token remains in the vault.
                _additionalLiquidity, //Additional Liquidity for AMM.
                _additionalLiquidityAmount1, //Token1 from AMM
                assets //Token0 from User
            );
        }
    }

    function _withdrawCallback(uint256 assets, bytes calldata withdrawConfig) internal override {
        uint256 _totalAssets = totalAssets();

        // Remove liquidity by shares and collect all fees
        (uint256 _burnedLiquidityAmount0, uint256 _burnedLiquidityAmount1) = _withdrawLiquidityByAssets(
            assets,
            _totalAssets,
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
    }

    function tendThis() external {}

    function _getUnderlyingAssets(
        int24 _lowerTick,
        int24 _upperTick
    ) internal view returns (UnderlyingAssets memory underlyingAssets) {
        uint128 liquidity = ICLAMMHelper(clammHelper).getCurrentLiquidity(clammPool, lowerTick, upperTick);
        // compute current holdings from liquidity
        if (liquidity > 0) {
            (underlyingAssets.liquidityAmount0, underlyingAssets.liquidityAmount1) = ICLAMMHelper(clammHelper)
                .getAmountsForLiquidity(clammPool, _lowerTick, _upperTick, liquidity);
        }

        (underlyingAssets.accruedFees0, underlyingAssets.accruedFees1) = ICLAMMHelper(clammHelper).getFeesEarned(
            clammPool,
            _lowerTick,
            _upperTick
        );

        underlyingAssets.vaultAmount0 = token0.balanceOf(address(this));
        underlyingAssets.vaultAmount1 = token1.balanceOf(address(this));
    }

    function _withdrawLiquidityByAssets(
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

    /*//////////////////////////////////////////////////////////////
                        Flashloan Functions
    //////////////////////////////////////////////////////////////*/

    function _triggerFlashloanForOverhedge(
        Positions memory additionalPosition,
        uint128 additionalLiquidity,
        uint256 additionalLiquidityAmount0,
        uint256 assets
    ) internal {
        bytes memory _userData = abi.encode(
            FlashloanType.DEPOSIT_OVERHEDGE,
            additionalPosition,
            additionalLiquidity,
            assets,
            msg.sender
        );

        flashloanHash = keccak256(_userData); //set storage for callback
        IBalancerVault(balancer).makeFlashLoan(
            IBalancerFlashLoanRecipient(address(this)),
            token0,
            additionalPosition.collateralAmount0 + additionalLiquidityAmount0 + 1,
            _userData
        );
    }

    function _triggerFlashloanForUnderhedge(
        Positions memory additionalPosition,
        uint128 additionalLiquidity,
        uint256 additionalLiquidityAmount1,
        uint256 assets
    ) internal {
        bytes memory _userData = abi.encode(
            FlashloanType.DEPOSIT_UNDERHEDGE,
            additionalPosition,
            additionalLiquidity,
            assets,
            msg.sender
        );
        flashloanHash = keccak256(_userData); //set storage for callback
        IBalancerVault(balancer).makeFlashLoan(
            IBalancerFlashLoanRecipient(address(this)),
            token1,
            additionalPosition.debtAmount1 > additionalLiquidityAmount1
                ? 0
                : additionalLiquidityAmount1 - additionalPosition.debtAmount1 + 1,
            _userData
        );
    }

    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory,
        bytes memory userData
    ) external {
        if (msg.sender != balancer) revert OnlyBalancerVault();
        //check validity
        if (flashloanHash == bytes32(0) || flashloanHash != keccak256(userData)) revert InvalidFlashloanHash();
        flashloanHash = bytes32(0); //clear cache

        uint8 _flashloanType = abi.decode(userData, (uint8));

        if (_flashloanType == uint8(FlashloanType.DEPOSIT_OVERHEDGE)) {
            (, Positions memory _pos, uint128 _liq, uint256 _assets, address _receiver) = abi.decode(
                userData,
                (uint8, Positions, uint128, uint256, address)
            );

            _execOverhedge(amounts[0], _assets, _liq, _pos);
        }

        if (_flashloanType == uint8(FlashloanType.DEPOSIT_UNDERHEDGE)) {
            (, Positions memory _pos, uint128 _liq, uint256 _assets, address _receiver) = abi.decode(
                userData,
                (uint8, Positions, uint128, uint256, address)
            );

            _execUnderHedge(_assets, _liq, _pos);
        }

        if (_flashloanType == uint8(FlashloanType.REDEEM)) {
            (, uint256 _amount1, uint256 _amount0) = abi.decode(userData, (uint8, uint256, uint256)); // (, debt, collateral)
            _execLiquidation(address(tokens[0]), amounts[0], _amount0, _amount1);
        }

        if (_flashloanType == uint8(FlashloanType.STOPLOSS)) {
            // TODO: implement this
        }

        //repay flashloan
        IERC20(tokens[0]).safeTransfer(balancer, amounts[0]);
    }

    function _execOverhedge(
        uint256 flashloanAmount0,
        uint256 assetUserProvided,
        uint128 additionalLiquidity,
        Positions memory positions
    ) internal {
        // Supply & Borrow
        ILendingHelper(lendingHelper).supply(lendingPool, address(token0), positions.collateralAmount0);
        ILendingHelper(lendingHelper).borrow(lendingPool, address(token1), positions.debtAmount1);

        // Add liquidity
        uint256 _additionalLiquidityAmount0;
        uint256 _additionalLiquidityAmount1;
        if (additionalLiquidity > 0) {
            (_additionalLiquidityAmount0, _additionalLiquidityAmount1) = ICLAMMHelper(clammHelper).mint(
                clammPool,
                lowerTick,
                upperTick,
                additionalLiquidity
            );
        }

        uint256 _surplusAmount1 = positions.debtAmount1 - (_additionalLiquidityAmount1 + positions.token1Balance);
        uint256 _amountOutFromSurplusToken1Sale = ISwapRouter(router).swapAmountIn(
            address(token1), //In
            address(token0), //Out
            routerFee,
            _surplusAmount1
        );

        uint256 _actualUsedAmount0 = flashloanAmount0 + positions.token0Balance - _amountOutFromSurplusToken1Sale;

        if (_actualUsedAmount0 > assetUserProvided) revert TooMuchTokenUsed();

        if (_actualUsedAmount0 < assetUserProvided) {
            //Refund the unspent Token0 (Leave some Token0 for #6)
            unchecked {
                token0.safeTransfer(msg.sender, assetUserProvided - _actualUsedAmount0);
            }
        }
    }

    function _execUnderHedge(
        uint256 assetUserProvided,
        uint128 additionalLiquidity,
        Positions memory positions
    ) internal {
        //Supply Token0 and Borrow Token1 (#1 and #2)
        ILendingHelper(lendingHelper).supply(lendingPool, address(token0), positions.collateralAmount0);
        ILendingHelper(lendingHelper).borrow(lendingPool, address(token1), positions.debtAmount1);

        //Add Liquidity (#3 and #4)
        uint256 _additionalLiquidityAmount0;
        uint256 _additionalLiquidityAmount1;
        if (additionalLiquidity > 0) {
            (_additionalLiquidityAmount0, _additionalLiquidityAmount1) = ICLAMMHelper(clammHelper).mint(
                address(clammPool),
                lowerTick,
                upperTick,
                additionalLiquidity
            );
        }

        // Token1 is flashLoaned.
        // Calculate the amount of Token1 needed to be swapped to repay the loan, then swap Token0=>Token1 (Swap more Token0 for Token1 to achieve #5)
        uint256 amount1ToBeSwapped = _additionalLiquidityAmount1 + positions.token1Balance - positions.debtAmount1;
        uint256 amount0UsedForToken1 = ISwapRouter(router).swapAmountOut(
            address(token0), //In
            address(token1), //Out
            routerFee,
            amount1ToBeSwapped
        );

        uint256 _actualUsedAmount0 = positions.collateralAmount0 +
            _additionalLiquidityAmount0 +
            positions.token0Balance +
            amount0UsedForToken1;

        //Refund the unspent Token0 (Leave some Token0 for #6)
        if (_actualUsedAmount0 < assetUserProvided) {
            //Refund the unspent Token0 (Leave some Token0 for #6)
            unchecked {
                token0.safeTransfer(msg.sender, assetUserProvided - _actualUsedAmount0);
            }
        }
    }

    function _execLiquidation(
        address flashloanToken0,
        uint256 flashloanAmount0,
        uint256 amount0,
        uint256 amount1
    ) internal {
        address _token0 = address(token0);
        address _token1 = address(token1);

        // repay debt
        ILendingHelper(lendingHelper).repay(lendingPool, _token1, amount1);

        // withdraw collateral
        ILendingHelper(lendingHelper).withdraw(lendingPool, _token0, amount0);

        //swap to repay flashloan
        if (flashloanAmount0 > 0) {
            (address _tokenAnother, address _tokenFlashLoaned) = (address(flashloanToken0) == _token0)
                ? (_token1, _token0)
                : (_token0, _token1);

            // Swap to repay the flash loaned token
            ISwapRouter(router).swapAmountOut(
                _tokenAnother, //In
                _tokenFlashLoaned, //Out
                routerFee,
                flashloanAmount0
            );
        }
    }
}
