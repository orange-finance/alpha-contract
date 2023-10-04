// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeStorageV1Initializable} from "@src/coreV1/proxy/OrangeStorageV1Initializable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IOrangeAlphaParameters} from "@src/interfaces/IOrangeAlphaParameters.sol";
import {ErrorsV1} from "@src/coreV1/ErrorsV1.sol";

abstract contract OrangeValidationCheckerInitializable is OrangeStorageV1Initializable {
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
}
