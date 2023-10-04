// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IERC20} from "@src/libs/BalancerFlashloan.sol";
import {IOrangeParametersV1} from "@src/interfaces/IOrangeParametersV1.sol";
import {IOrangeStorageV1} from "@src/interfaces/IOrangeStorageV1.sol";
import {OrangeERC20Initializable, IERC20Decimals} from "@src/coreV1/proxy/OrangeERC20Initializable.sol";

abstract contract OrangeStorageV1Initializable is IOrangeStorageV1, OrangeERC20Initializable {
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

    function decimals() public view override returns (uint8) {
        return IERC20Decimals(address(token0)).decimals();
    }
}
