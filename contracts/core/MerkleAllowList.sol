// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

abstract contract MerkleAllowList {
    event AllowlistEnabled(bool enabled);
    event MerkleRootUpdated(bytes32 merkleRoot);

    bytes32 public merkleRoot;
    bool public allowlistEnabled = true;

    function _setMerkleRoot(bytes32 _merkleRoot) internal {
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(merkleRoot);
    }

    function _setAllowlistEnabled(bool _allowlistEnabled) internal {
        allowlistEnabled = _allowlistEnabled;
        emit AllowlistEnabled(_allowlistEnabled);
    }

    modifier onlyAllowlisted(bytes32[] calldata merkleProof) {
        if (allowlistEnabled) {
            require(
                _isAllowlisted(msg.sender, merkleProof),
                "MerkleAllowList: Caller is not on allowlist."
            );
        }
        _;
    }

    function _isAllowlisted(address account, bytes32[] calldata merkleProof)
        internal
        view
        virtual
        returns (bool)
    {
        bytes32 node = keccak256(abi.encodePacked(account));
        return MerkleProof.verify(merkleProof, merkleRoot, node);
    }
}
