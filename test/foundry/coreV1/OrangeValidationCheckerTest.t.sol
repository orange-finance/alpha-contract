// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {OrangeValidationChecker, ErrorsV1} from "../../../contracts/coreV1/OrangeValidationChecker.sol";
import {OrangeERC20} from "../../../contracts/coreV1/OrangeERC20.sol";
import {OrangeParametersV1} from "../../../contracts/coreV1/OrangeParametersV1.sol";

contract OrangeValidationCheckerTest is BaseTest {
    AddressHelper.TokenAddr public tokenAddr;

    OrangeParametersV1 public params;

    OrangeValidationCheckerMock checker;

    //parameters
    uint256 constant DEPOSIT_CAP = 1_000_000 * 1e6;

    function setUp() public {
        (tokenAddr, , ) = AddressHelper.addresses(block.chainid);

        //deploy parameters
        params = new OrangeParametersV1();

        //set parameters
        params.setAllowlistEnabled(false); //merkle allow list off

        checker = new OrangeValidationCheckerMock(address(params));
    }
}

contract OrangeValidationCheckerMock is OrangeValidationChecker {
    constructor(address _params) OrangeERC20("OrangeStrategyImplV1", "OrangeStrategyImplV1") {
        params = OrangeParametersV1(_params);
    }

    function execAllowlisted(bytes32[] calldata _merkleProof) external view Allowlisted(_merkleProof) returns (bool) {
        return true;
    }
}
