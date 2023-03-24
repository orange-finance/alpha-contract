// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IOrangeAlphaPeriphery, IOrangeAlphaVault, IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaPeriphery.sol";

// import "forge-std/console2.sol";

contract OrangeAlphaPeriphery is IOrangeAlphaPeriphery {
    using SafeERC20 for IERC20;

    /* ========== ERRORS ========== */
    string constant ERROR_MERKLE_ALLOWLISTED = "MERKLE_ALLOWLISTED";
    string constant ERROR_CAPOVER = "CAPOVER";
    string constant ERROR_LOCKUP = "LOCKUP";

    /* ========== STORAGES ========== */
    mapping(address => DepositType) public deposits;
    uint256 public totalDeposits;

    /* ========== PARAMETERS ========== */
    IOrangeAlphaVault public vault;
    IOrangeAlphaParameters public params;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault, address _params) {
        vault = IOrangeAlphaVault(_vault);
        params = IOrangeAlphaParameters(_params);
        vault.token1().safeApprove(address(vault), type(uint256).max);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function deposit(uint256 _shares, uint256 _maxAssets, bytes32[] calldata merkleProof) external returns (uint256) {
        //validation of merkle proof
        _validateSenderAllowlisted(msg.sender, merkleProof);

        //validation of deposit caps
        if (deposits[msg.sender].assets + _maxAssets > params.depositCap()) {
            revert(ERROR_CAPOVER);
        }
        deposits[msg.sender].assets += _maxAssets;
        deposits[msg.sender].timestamp = uint40(block.timestamp);
        uint256 _totalDeposits = totalDeposits;
        if (_totalDeposits + _maxAssets > params.totalDepositCap()) {
            revert(ERROR_CAPOVER);
        }
        totalDeposits = _totalDeposits + _maxAssets;

        //transfer USDC
        vault.token1().safeTransferFrom(msg.sender, address(this), _maxAssets);
        return vault.deposit(_shares, msg.sender, _maxAssets);
    }

    function redeem(uint256 _shares, uint256 _minAssets) external returns (uint256) {
        if (block.timestamp < deposits[msg.sender].timestamp + params.lockupPeriod()) {
            revert(ERROR_LOCKUP);
        }
        uint256 _assets = vault.redeem(_shares, msg.sender, msg.sender, _minAssets);

        //subtract depositsCap
        uint256 _deposited = deposits[msg.sender].assets;
        if (_deposited < _assets) {
            deposits[msg.sender].assets = 0;
        } else {
            unchecked {
                deposits[msg.sender].assets -= _assets;
            }
        }
        if (totalDeposits < _assets) {
            totalDeposits = 0;
        } else {
            unchecked {
                totalDeposits -= _assets;
            }
        }
        return _assets;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _validateSenderAllowlisted(address _account, bytes32[] calldata _merkleProof) internal view virtual {
        if (params.allowlistEnabled()) {
            if (!MerkleProof.verify(_merkleProof, params.merkleRoot(), keccak256(abi.encodePacked(_account)))) {
                revert(ERROR_MERKLE_ALLOWLISTED);
            }
        }
    }
}
