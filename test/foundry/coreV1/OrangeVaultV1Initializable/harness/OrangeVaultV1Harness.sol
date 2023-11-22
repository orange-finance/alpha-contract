// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeVaultV1Initializable} from "@src/coreV1/proxy/OrangeVaultV1Initializable.sol";

contract OrangeVaultV1Harness is OrangeVaultV1Initializable {
    int24 public avgTick;

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
