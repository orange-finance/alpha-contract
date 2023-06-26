// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeVaultV1, IERC20} from "../coreV1/OrangeVaultV1.sol";
import {FullMath} from "../libs/uniswap/LiquidityAmounts.sol";

// import "forge-std/console2.sol";

contract OrangeVaultV1Mock is OrangeVaultV1 {
    // uint256 MAGIC_SCALE_1E8 = 1e8; //for computing ltv

    int24 public avgTick;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        address _token0,
        address _token1,
        address _liquidityPool,
        address _lendingPool,
        address _params,
        address _router,
        uint24 _routerFee,
        address _balancer
    )
        OrangeVaultV1(
            _name,
            _symbol,
            _token0,
            _token1,
            _liquidityPool,
            _lendingPool,
            _params,
            _router,
            _routerFee,
            _balancer
        )
    {
        // console.log("OrangeVaultV1Mock deployed");
    }

    /* ========== ONLY MOCK FUNCTIONS ========== */

    function setAvgTick(int24 _avgTick) external {
        avgTick = _avgTick;
    }

    /* ========== VIEW FUNCTIONS(INTERNAL) ========== */
    function alignTotalAsset(
        uint256 amount0Current,
        uint256 amount1Current,
        uint256 amount0Debt,
        uint256 amount1Supply
    ) external view returns (uint256 totalAlignedAssets) {
        return _alignTotalAsset(amount0Current, amount1Current, amount0Debt, amount1Supply);
    }

    function computeTargetPositionByShares(
        uint256 _collateralAmount0,
        uint256 _debtAmount1,
        uint256 _token0Balance,
        uint256 _token1Balance,
        uint256 _shares,
        uint256 _totalSupply
    ) external pure returns (Positions memory _position) {
        return
            _computeTargetPositionByShares(
                _collateralAmount0,
                _debtAmount1,
                _token0Balance,
                _token1Balance,
                _shares,
                _totalSupply
            );
    }

    /* ========== WRITE FUNCTIONS(EXTERNAL) ========== */
    function addLiquidityInRebalance(int24, int24, uint256, uint256) external {
        _delegate(params.strategyImpl());
    }

    /* ========== CALLBACK FUNCTIONS ========== */
}
