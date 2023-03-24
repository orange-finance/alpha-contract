// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface IResolver {
    function checker() external view returns (bool canExec, bytes memory execPayload);
}
