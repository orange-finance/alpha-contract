// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {MerkleAllowList} from "../core/MerkleAllowList.sol";

contract MerkleAllowListMock is MerkleAllowList {
    function exec(bytes32[] calldata merkleProof)
        external
        onlyAllowlisted(merkleProof)
    {}

    function setMerkleRoot(bytes32 merkleRoot_) external {
        _setMerkleRoot(merkleRoot_);
    }

    function setAllowlistEnabled(bool _allowlistEnabled) external {
        _setAllowlistEnabled(_allowlistEnabled);
    }
}
