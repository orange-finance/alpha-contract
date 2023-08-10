// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeValidationChecker} from "../coreV1/OrangeValidationChecker.sol";
import {OrangeERC20} from "../coreV1/OrangeERC20.sol";
import {IOrangeParametersV1} from "../interfaces/IOrangeParametersV1.sol";

contract OrangeValidationCheckerMock is OrangeValidationChecker {
    constructor(address _params) OrangeERC20("OrangeValidationCheckerMock", "OrangeValidationCheckerMock") {
        params = IOrangeParametersV1(_params);
    }

    function exec(bytes32[] calldata _merkleProof) external Allowlisted(_merkleProof) {}
}
