// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

abstract contract MerkleAllowList {
    bytes32 public immutable merkleRoot;

    constructor(bytes32 merkleRoot_) {
        merkleRoot = merkleRoot_;
    }

    modifier onlyAllowlisted(uint256 index, bytes32[] calldata merkleProof) {
        require(
            _isAllowlisted(index, msg.sender, merkleProof),
            "MerkleAllowList: Caller is not on allowlist."
        );
        _;
    }

    function _isAllowlisted(
        uint256 index,
        address account,
        bytes32[] calldata merkleProof
    ) internal view virtual returns (bool) {
        bytes32 node = keccak256(abi.encodePacked(index, account));
        return MerkleProof.verify(merkleProof, merkleRoot, node);
    }
}