// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeStorageV1} from "./OrangeStorageV1.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";
import {ErrorsV1} from "./ErrorsV1.sol";

abstract contract OrangeValidationChecker is OrangeStorageV1 {
    using SafeERC20 for IERC20;

    /* ========== MODIFIER ========== */
    modifier Allowlisted(bytes32[] calldata merkleProof) {
        _validateSenderAllowlisted(msg.sender, merkleProof);
        _;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _validateSenderAllowlisted(address _account, bytes32[] calldata _merkleProof) internal view {
        if (params.allowlistEnabled()) {
            if (!MerkleProof.verify(_merkleProof, params.merkleRoot(), keccak256(abi.encodePacked(_account)))) {
                revert(ErrorsV1.MERKLE_ALLOWLISTED);
            }
        }
    }

    function _addDepositCap(uint256 _assets) internal {
        if (deposits[msg.sender].assets + _assets > params.depositCap()) {
            revert(ErrorsV1.CAPOVER);
        }
        deposits[msg.sender].assets += _assets;
        deposits[msg.sender].timestamp = uint40(block.timestamp);
        uint256 _totalDeposits = totalDeposits;
        if (_totalDeposits + _assets > params.totalDepositCap()) {
            revert(ErrorsV1.CAPOVER);
        }
        totalDeposits = _totalDeposits + _assets;
    }

    function _reduceDepositCap(uint256 _assets) internal {
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
    }
}
