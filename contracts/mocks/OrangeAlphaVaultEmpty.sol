// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";

// import {Gelatofied} from "../abstract/Gelatofied.sol";

// import "forge-std/console2.sol";

contract OrangeAlphaVaultEmpty is IOrangeAlphaVault, ERC20, Ownable {
    /* ========== CONSTANTS ========== */
    uint256 MAGIC_SCALE_1E4 = 1e4; //for ltv
    uint256 MAGIC_SCALE_1E8 = 1e8; //for computing ltv from Aave

    /* ========== STORAGES ========== */
    mapping(address => DepositType) public override deposits;
    uint256 public override totalDeposits;

    int24 public lowerTick;
    int24 public upperTick;
    uint8 _decimal;

    /* ========== PARAMETERS ========== */
    uint256 _depositCap;
    uint256 public override totalDepositCap;
    uint16 public slippageBPS;
    uint32 public slippageInterval;
    uint32 public maxLtv;

    /* ========== CONSTRUCTOR ========== */
    constructor(
        string memory _name,
        string memory _symbol,
        address,
        address,
        int24 _lowerTick,
        int24 _upperTick
    ) ERC20(_name, _symbol) {
        _decimal = 6;

        // these variables can be udpated by the manager
        slippageBPS = 500; // default: 5% slippage
        slippageInterval = 5 minutes;
        _depositCap = 1_000_000 * 1e6;
        totalDepositCap = 1_000_000 * 1e6;
        maxLtv = 8500; //85%

        //setting ticks
        lowerTick = _lowerTick;
        upperTick = _upperTick;
    }

    /* ========== VIEW FUNCTIONS ========== */
    function totalAssets() external pure returns (uint256) {
        return 10_000 * 1e6;
    }

    function convertToShares(uint256 _assets) external pure returns (uint256) {
        return _assets;
    }

    function convertToAssets(uint256 _shares) external pure returns (uint256) {
        return _shares;
    }

    /// @dev deprecated
    function assetPerShare() external view returns (uint256 assets) {}

    ///@dev unused
    function getAavePoolLtv() external pure returns (uint256) {
        return 0;
    }

    function depositCap(address) public view returns (uint256) {
        return _depositCap;
    }

    function getPositionID() public view returns (bytes32 positionID) {
        return _getPositionID(lowerTick, upperTick);
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {}

    // @inheritdoc ERC20
    function decimals() public view override returns (uint8) {
        return _decimal;
    }

    function _getPositionID(int24 _lowerTick, int24 _upperTick)
        internal
        view
        returns (bytes32 positionID)
    {
        return
            keccak256(abi.encodePacked(address(this), _lowerTick, _upperTick));
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function deposit(
        uint256 _assets,
        address,
        uint256
    ) external returns (uint256 shares_) {
        return _assets;
    }

    function redeem(
        uint256 _shares,
        address,
        address,
        uint256
    ) external returns (uint256 assets_) {
        return _shares;
    }

    /// @dev similar to Arrakis' executiveRebalance
    function rebalance(int24, int24) external onlyOwner {}

    function emitAction() external {}

    function stoploss() external onlyOwner {}

    function removeAllPosition() external onlyOwner {}

    function setDepositCap(uint256 __depositCap, uint256 _totalDepositCap)
        external
        onlyOwner
    {
        if (__depositCap > _totalDepositCap) {
            revert InvalidParamsCap();
        }
        _depositCap = __depositCap;
        totalDepositCap = _totalDepositCap;
        emit UpdateDepositCap(__depositCap, _totalDepositCap);
    }

    function setSlippage(uint16 _slippageBPS, uint32 _slippageInterval)
        external
        onlyOwner
    {
        if (_slippageBPS > MAGIC_SCALE_1E4) {
            revert InvalidParamsBps();
        }
        if (_slippageInterval == 0) {
            revert InvalidParamsInterval();
        }
        slippageBPS = _slippageBPS;
        slippageInterval = _slippageInterval;
        emit UpdateSlippage(_slippageBPS, _slippageInterval);
    }

    function setMaxLtv(uint32 _maxLtv) external onlyOwner {
        if (_maxLtv > MAGIC_SCALE_1E8) {
            revert InvalidParamsLtv();
        }
        maxLtv = _maxLtv;
        emit UpdateMaxLtv(_maxLtv);
    }
}
