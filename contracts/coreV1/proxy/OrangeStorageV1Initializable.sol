// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IERC20} from "@src/libs/BalancerFlashloan.sol";
import {IOrangeParametersV1} from "@src/interfaces/IOrangeParametersV1.sol";
import {IOrangeStorageV1} from "@src/interfaces/IOrangeStorageV1.sol";

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract OrangeStorageV1Initializable is Initializable, IOrangeStorageV1 {
    struct DepositType {
        uint256 assets;
        uint40 timestamp;
    }

    //OrangeVault
    int24 public lowerTick;
    int24 public upperTick;
    bool public hasPosition;
    bytes32 public flashloanHash; //cache flashloan hash to check validity

    /* ========== PARAMETERS ========== */
    address public liquidityPool;
    address public lendingPool;
    IERC20 public token0; //collateral and deposited currency by users
    IERC20 public token1; //debt and hedge target token
    IOrangeParametersV1 public params;
    address public router;
    uint24 public routerFee;
    address public balancer;
}
