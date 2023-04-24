// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// import "forge-std/console2.sol";

contract MerkleAllowListMock {
    uint public counter;
    bytes32 public merkleRoot;

    function setMerkleRoot(bytes32 _merkleRoot) external {
        merkleRoot = _merkleRoot;
    }

    function exec(bytes32[] calldata merkleProof) external {
        //validation of merkle proof
        _validateSenderAllowlisted(msg.sender, merkleProof);
        counter++;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _validateSenderAllowlisted(address _account, bytes32[] calldata _merkleProof) internal view virtual {
        if (!MerkleProof.verify(_merkleProof, merkleRoot, keccak256(abi.encodePacked(_account)))) {
            revert("MerkleAllowList: Caller is not on allowlist.");
        }
    }
}
