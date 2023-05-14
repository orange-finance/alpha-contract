// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IAaveLendingPoolManager} from "../interfaces/IAaveLendingPoolManager.sol";
import {IOrangePoolManagerProxy} from "../interfaces/IOrangePoolManagerProxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {IAaveV3Pool, SafeAavePool} from "../libs/SafeAavePool.sol";
import {DataTypes} from "../vendor/aave/DataTypes.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//libraries
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "forge-std/console2.sol";

contract AaveLendingPoolManager is IAaveLendingPoolManager, Initializable, IOrangePoolManagerProxy {
    // TODO cap

    using SafeERC20 for IERC20;
    using SafeAavePool for IAaveV3Pool;

    /* ========== Structs ========== */

    /* ========== CONSTANTS ========== */
    uint16 constant AAVE_REFERRAL_NONE = 0;
    uint256 constant AAVE_VARIABLE_INTEREST = 2;

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
    function initialize(
        address _operator,
        address _token0,
        address _token1,
        uint256[] calldata,
        address[] calldata _references
    ) external initializer {
        operator = _operator;
        aave = IAaveV3Pool(_references[0]);

        token0 = IERC20(_token0);
        DataTypes.ReserveData memory reserveDataBase = aave.getReserveData(_token0);
        aToken0 = IERC20(reserveDataBase.aTokenAddress);

        token1 = IERC20(_token1);
        DataTypes.ReserveData memory reserveDataTarget = aave.getReserveData(_token1);
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
        if (amount > 0) {
            token0.safeTransferFrom(operator, address(this), amount);
        }
        aave.safeSupply(address(token0), amount, address(this), AAVE_REFERRAL_NONE);
    }

    function withdraw(uint256 amount) external onlyOperator {
        aave.safeWithdraw(address(token0), amount, operator);
    }

    function borrow(uint256 amount) external onlyOperator {
        aave.safeBorrow(address(token1), amount, AAVE_VARIABLE_INTEREST, AAVE_REFERRAL_NONE, address(this));
        if (amount > 0) {
            token1.safeTransfer(operator, amount);
        }
    }

    function repay(uint256 amount) external onlyOperator {
        if (amount > 0) {
            token1.safeTransferFrom(operator, address(this), amount);
        }
        aave.safeRepay(address(token1), amount, AAVE_VARIABLE_INTEREST, address(this));
    }
}
