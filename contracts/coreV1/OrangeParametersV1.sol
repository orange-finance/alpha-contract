// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {Ownable} from "../libs/Ownable.sol";
import {ErrorsV1} from "./ErrorsV1.sol";
import {IOrangeParametersV1} from "../interfaces/IOrangeParametersV1.sol";

contract OrangeParametersV1 is IOrangeParametersV1, Ownable {
    /* ========== CONSTANTS ========== */
    uint256 private constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 private constant MAGIC_SCALE_1E4 = 10000; //for slippage

    /* ========== PARAMETERS ========== */
    uint16 public slippageBPS;
    uint24 public tickSlippageBPS;
    uint32 public twapSlippageInterval;
    uint32 public maxLtv;
    bool public allowlistEnabled;
    bytes32 public merkleRoot;
    uint256 public depositCap;
    uint256 public minDepositAmount;
    address public helper;
    address public strategyImpl;

    /* ========== CONSTRUCTOR ========== */
    constructor() {
        slippageBPS = 500; // default: 5% slippage
        tickSlippageBPS = 10;
        twapSlippageInterval = 5 minutes;
        maxLtv = 80000000; //80%
        allowlistEnabled = true;
    }

    /**
     * @notice Set parameters of slippage
     * @param _slippageBPS Slippage BPS
     * @param _tickSlippageBPS Check ticks BPS
     */
    function setSlippage(uint16 _slippageBPS, uint24 _tickSlippageBPS) external onlyOwner {
        if (_tickSlippageBPS == 0) revert(ErrorsV1.ZERO_INTEGER);

        if (_slippageBPS > MAGIC_SCALE_1E4) {
            revert(ErrorsV1.INVALID_PARAM);
        }
        slippageBPS = _slippageBPS;
        tickSlippageBPS = _tickSlippageBPS;

        emit SetSlippage(_slippageBPS, _tickSlippageBPS);
    }

    /**
     * @notice Set parameters of twap slippage
     * @param _twapSlippageInterval TWAP slippage interval
     */
    function setTwapSlippageInterval(uint32 _twapSlippageInterval) external onlyOwner {
        if (_twapSlippageInterval == 0) revert(ErrorsV1.ZERO_INTEGER);
        twapSlippageInterval = _twapSlippageInterval;

        emit SetTwapSlippageInterval(_twapSlippageInterval);
    }

    /**
     * @notice Set parameters of max LTV
     * @param _maxLtv Max LTV
     */
    function setMaxLtv(uint32 _maxLtv) external onlyOwner {
        if (_maxLtv > MAGIC_SCALE_1E8) {
            revert(ErrorsV1.INVALID_PARAM);
        }
        maxLtv = _maxLtv;

        emit SetMaxLtv(_maxLtv);
    }

    /**
     * @notice Set parameters of allowlist
     * @param _allowlistEnabled true or false
     */
    function setAllowlistEnabled(bool _allowlistEnabled) external onlyOwner {
        allowlistEnabled = _allowlistEnabled;

        emit SetAllowlistEnabled(_allowlistEnabled);
    }

    /**
     * @notice Set parameters of merkle root
     * @param _merkleRoot Merkle root
     */
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;

        emit SetMerkleRoot(_merkleRoot);
    }

    /**
     * @notice Set parameters of depositCap
     * @param _depositCap Deposit cap of each accounts
     */
    function setDepositCap(uint256 _depositCap) external onlyOwner {
        if (_depositCap == 0) revert(ErrorsV1.ZERO_INTEGER);
        depositCap = _depositCap;

        emit SetDepositCap(_depositCap);
    }

    /**
     * @notice Set parameters of minDepositAmount
     * @param _minDepositAmount Min deposit amount
     */
    function setMinDepositAmount(uint256 _minDepositAmount) external onlyOwner {
        if (_minDepositAmount == 0) revert(ErrorsV1.ZERO_INTEGER);
        minDepositAmount = _minDepositAmount;

        emit SetMinDepositAmount(_minDepositAmount);
    }

    /**
     * @notice Set parameters of Rebalancer
     * @param _helper Helper
     */
    function setHelper(address _helper) external onlyOwner {
        if (_helper == address(0)) revert(ErrorsV1.ZERO_ADDRESS);

        helper = _helper;

        emit SetHelper(_helper);
    }

    /**
     * @notice Set parameters of strategyImpl
     * @param _strategyImpl strategyImpl
     */
    function setStrategyImpl(address _strategyImpl) external onlyOwner {
        if (_strategyImpl == address(0)) revert(ErrorsV1.ZERO_ADDRESS);

        strategyImpl = _strategyImpl;

        emit SetStrategyImpl(_strategyImpl);
    }
}
