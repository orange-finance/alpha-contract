// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {ILendingPoolManager} from "../interfaces/ILendingPoolManager.sol";

import {IAaveV3Pool, SafeAavePool} from "../libs/SafeAavePool.sol";
import {DataTypes} from "../vendor/aave/DataTypes.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "forge-std/console2.sol";

contract AaveLendingPoolManager is ILendingPoolManager {
    using SafeERC20 for IERC20;
    using SafeAavePool for IAaveV3Pool;

    /* ========== Structs ========== */

    /* ========== CONSTANTS ========== */
    uint16 constant AAVE_REFERRAL_NONE = 0;
    uint256 constant AAVE_VARIABLE_INTEREST = 2;

    /* ========== STORAGES ========== */

    /* ========== PARAMETERS ========== */
    IAaveV3Pool public immutable aave;
    IERC20 public immutable token0;
    IERC20 public immutable token1;
    IERC20 public immutable aToken0;
    IERC20 public immutable debtToken1;
    address public immutable vault;

    /* ========== MODIFIER ========== */
    modifier onlyVault() {
        if (msg.sender != vault) revert("ONLY_VAULT");
        _;
    }

    /* ========== INITIALIZER ========== */
    constructor(address _vault, address _token0, address _token1, address _aave) {
        vault = _vault;
        aave = IAaveV3Pool(_aave);

        token0 = IERC20(_token0);
        DataTypes.ReserveData memory reserveDataBase = aave.getReserveData(_token0);
        if (reserveDataBase.aTokenAddress == address(0)) {
            revert("INVALID_TOKEN0");
        }
        aToken0 = IERC20(reserveDataBase.aTokenAddress);

        token1 = IERC20(_token1);
        DataTypes.ReserveData memory reserveDataTarget = aave.getReserveData(_token1);
        if (reserveDataTarget.variableDebtTokenAddress == address(0)) {
            revert("INVALID_TOKEN1");
        }
        debtToken1 = IERC20(reserveDataTarget.variableDebtTokenAddress);

        token0.safeApprove(address(aave), type(uint256).max);
        token1.safeApprove(address(aave), type(uint256).max);
    }

    function balances() external view returns (uint256, uint256) {
        return (aToken0.balanceOf(address(this)), debtToken1.balanceOf(address(this)));
    }

    function balanceOfCollateral() external view returns (uint256) {
        return aToken0.balanceOf(address(this));
    }

    function balanceOfDebt() external view returns (uint256) {
        return debtToken1.balanceOf(address(this));
    }

    function supply(uint256 _amount0) external onlyVault {
        if (_amount0 > 0) {
            token0.safeTransferFrom(vault, address(this), _amount0);
        }
        aave.safeSupply(address(token0), _amount0, address(this), AAVE_REFERRAL_NONE);
    }

    function withdraw(uint256 _amount0) external onlyVault {
        aave.safeWithdraw(address(token0), _amount0, vault);
    }

    function borrow(uint256 _amount1) external onlyVault {
        aave.safeBorrow(address(token1), _amount1, AAVE_VARIABLE_INTEREST, AAVE_REFERRAL_NONE, address(this));
        if (_amount1 > 0) {
            token1.safeTransfer(vault, _amount1);
        }
    }

    function repay(uint256 _amount1) external onlyVault {
        if (_amount1 > 0) {
            token1.safeTransferFrom(vault, address(this), _amount1);
        }
        aave.safeRepay(address(token1), _amount1, AAVE_VARIABLE_INTEREST, address(this));
    }
}
