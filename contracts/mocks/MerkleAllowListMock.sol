// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {MerkleAllowList} from "../core/MerkleAllowList.sol";

contract MerkleAllowListMock is MerkleAllowList {
    constructor(bytes32 merkleRoot_) MerkleAllowList(merkleRoot_) {}

    function exec(bytes32[] calldata merkleProof)
        external
        onlyAllowlisted(merkleProof)
    {}
}
