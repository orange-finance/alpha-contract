// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {Ownable} from "../libs/Ownable.sol";
import {GelatoOps} from "../libs/GelatoOps.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaParameters is IOrangeAlphaParameters, Ownable {
    /* ========== CONSTANTS ========== */
    uint256 constant MAGIC_SCALE_1E8 = 1e8; //for computing ltv
    uint16 constant MAGIC_SCALE_1E4 = 10000; //for slippage
    string constant PARAM = "P";

    /* ========== PARAMETERS ========== */
    uint256 public depositCap;
    uint256 public totalDepositCap;
    uint256 public minDepositAmount;
    uint16 public slippageBPS;
    uint24 public tickSlippageBPS;
    uint32 public twapSlippageInterval;
    uint32 public maxLtv;
    uint40 public lockupPeriod;
    mapping(address => bool) public strategists;
    bool public allowlistEnabled;
    bytes32 public merkleRoot;
    address public gelato;
    address public periphery;

    /* ========== CONSTRUCTOR ========== */
    constructor() {
        // these variables can be udpated by the manager
        depositCap = 1_000_000 * 1e6;
        totalDepositCap = 1_000_000 * 1e6;
        minDepositAmount = 100 * 1e6;
        slippageBPS = 500; // default: 5% slippage
        tickSlippageBPS = 10;
        twapSlippageInterval = 5 minutes;
        maxLtv = 80000000; //80%
        lockupPeriod = 7 days;
        strategists[msg.sender] = true;
        allowlistEnabled = true;
        _setGelato(msg.sender);
    }

    /**
     * @notice Set parameters of depositCap
     * @param _depositCap Deposit cap of each accounts
     * @param _totalDepositCap Total deposit cap
     */
    function setDepositCap(uint256 _depositCap, uint256 _totalDepositCap) external onlyOwner {
        if (_depositCap > _totalDepositCap) {
            revert(PARAM);
        }
        depositCap = _depositCap;
        totalDepositCap = _totalDepositCap;
    }

    /**
     * @notice Set parameters of minDepositAmount
     * @param _minDepositAmount Min deposit amount
     */
    function setMinDepositAmount(uint256 _minDepositAmount) external onlyOwner {
        minDepositAmount = _minDepositAmount;
    }

    /**
     * @notice Set parameters of slippage
     * @param _slippageBPS Slippage BPS
     * @param _tickSlippageBPS Check ticks BPS
     */
    function setSlippage(uint16 _slippageBPS, uint24 _tickSlippageBPS) external onlyOwner {
        if (_slippageBPS > MAGIC_SCALE_1E4) {
            revert(PARAM);
        }
        slippageBPS = _slippageBPS;
        tickSlippageBPS = _tickSlippageBPS;
    }

    /**
     * @notice Set parameters of lockup period
     * @param _twapSlippageInterval TWAP slippage interval
     */
    function setTwapSlippageInterval(uint32 _twapSlippageInterval) external onlyOwner {
        twapSlippageInterval = _twapSlippageInterval;
    }

    /**
     * @notice Set parameters of max LTV
     * @param _maxLtv Max LTV
     */
    function setMaxLtv(uint32 _maxLtv) external onlyOwner {
        if (_maxLtv > MAGIC_SCALE_1E8) {
            revert(PARAM);
        }
        maxLtv = _maxLtv;
    }

    /**
     * @notice Set parameters of lockup period
     * @param _lockupPeriod Lockup period
     */
    function setLockupPeriod(uint40 _lockupPeriod) external onlyOwner {
        lockupPeriod = _lockupPeriod;
    }

    /**
     * @notice Set parameters of Rebalancer
     * @param _strategist Strategist
     * @param _is true or false
     */
    function setStrategist(address _strategist, bool _is) external onlyOwner {
        strategists[_strategist] = _is;
    }

    function setAllowlistEnabled(bool _allowlistEnabled) external onlyOwner {
        allowlistEnabled = _allowlistEnabled;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setGelato(address _gelato) external onlyOwner {
        _setGelato(_gelato);
    }

    function _setGelato(address _gelato) internal {
        gelato = GelatoOps.getDedicatedMsgSender(_gelato);
    }

    function setPeriphery(address _periphery) external onlyOwner {
        periphery = _periphery;
    }
}
