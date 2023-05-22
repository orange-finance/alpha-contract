// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import "forge-std/console2.sol";
import {IERC20} from "../libs/BalancerFlashloan.sol";
import {IOrangeParametersV1} from "../interfaces/IOrangeParametersV1.sol";
import {IOrangeBaseV1} from "../interfaces/IOrangeBaseV1.sol";

abstract contract OrangeBaseV1 is IOrangeBaseV1 {
    struct DepositType {
        uint256 assets;
        uint40 timestamp;
    }

    //ERC20
    string public name;
    string public symbol;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    //OrangeVault
    int24 public lowerTick;
    int24 public upperTick;
    bool public hasPosition;
    bytes32 public flashloanHash; //tempolary use in flashloan

    //Checker
    mapping(address => DepositType) public deposits;
    uint256 public totalDeposits;

    /* ========== PARAMETERS ========== */
    address public liquidityPool;
    address public lendingPool;
    IERC20 public token0; //collateral and deposited currency by users
    IERC20 public token1; //debt and hedge target token
    IOrangeParametersV1 public params;
}
