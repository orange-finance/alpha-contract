// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IAaveLendingPoolManager} from "../interfaces/IAaveLendingPoolManager.sol";
import {IProxy} from "../interfaces/IProxy.sol";
import {Initializable} from "../libs/Initializable.sol";

import {IAaveV3Pool, SafeAavePool} from "../libs/SafeAavePool.sol";
import {DataTypes} from "../vendor/aave/DataTypes.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "forge-std/console2.sol";

contract AaveLendingPoolManager is IAaveLendingPoolManager, Initializable, IProxy {
    // TODO cap

    using SafeERC20 for IERC20;
    using SafeAavePool for IAaveV3Pool;

    /* ========== Structs ========== */

    /* ========== CONSTANTS ========== */
    uint16 constant AAVE_REFERRAL_NONE = 0; //for aave
    uint256 constant AAVE_VARIABLE_INTEREST = 2; //for aave

    /* ========== STORAGES ========== */

    /* ========== PARAMETERS ========== */
    IAaveV3Pool public aave;
    IERC20 public token0;
    IERC20 public token1;
    IERC20 public aToken0;
    IERC20 public debtToken1;
    address public operator;

    /* ========== MODIFIER ========== */
    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator can call this function");
        _;
    }

    /* ========== INITIALIZER ========== */
    /**
     * @notice
     * @param _params none
     * @param _references 0: operator, 1: aave pool, 2: baseToken, 3: targetToken
     */
    function initialize(uint256[] calldata, address[] calldata _references) external initializer {
        operator = _references[0];
        aave = IAaveV3Pool(_references[1]);

        token0 = IERC20(_references[2]);
        DataTypes.ReserveData memory reserveDataBase = aave.getReserveData(_references[2]);
        aToken0 = IERC20(reserveDataBase.aTokenAddress);

        token1 = IERC20(_references[3]);
        DataTypes.ReserveData memory reserveDataTarget = aave.getReserveData(_references[3]);
        debtToken1 = IERC20(reserveDataTarget.variableDebtTokenAddress);

        token0.safeApprove(address(aave), type(uint256).max);
        token1.safeApprove(address(aave), type(uint256).max);
    }

    function balanceOfCollateral() external view returns (uint256) {
        return aToken0.balanceOf(address(this));
    }

    function balanceOfDebt() external view returns (uint256) {
        return debtToken1.balanceOf(address(this));
    }

    function supply(uint256 amount) external onlyOperator {
        token0.safeTransferFrom(operator, address(this), amount);
        aave.safeSupply(address(token0), amount, address(this), AAVE_REFERRAL_NONE);
    }

    function withdraw(uint256 amount) external onlyOperator {
        aave.safeWithdraw(address(token0), amount, operator);
    }

    function borrow(uint256 amount) external onlyOperator {
        aave.safeBorrow(address(token1), amount, AAVE_VARIABLE_INTEREST, AAVE_REFERRAL_NONE, address(this));
        token1.transfer(operator, amount);
    }

    function repay(uint256 amount) external onlyOperator {
        token1.safeTransferFrom(operator, address(this), amount);
        aave.safeRepay(address(token1), amount, AAVE_VARIABLE_INTEREST, address(this));
    }
}
