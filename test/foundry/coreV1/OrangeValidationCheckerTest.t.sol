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
    uint256 constant TOTAL_DEPOSIT_CAP = 1_000_000 * 1e6;

    function setUp() public {
        (tokenAddr, , ) = AddressHelper.addresses(block.chainid);

        //deploy parameters
        params = new OrangeParametersV1();

        //set parameters
        params.setDepositCap(DEPOSIT_CAP, TOTAL_DEPOSIT_CAP);
        params.setAllowlistEnabled(false); //merkle allow list off

        checker = new OrangeValidationCheckerMock(address(params));
    }

    /* ========== FUNCTIONS ========== */
    function test_addDeposit_Revert1() public {
        //deposit cap over
        vm.expectRevert(bytes(ErrorsV1.CAPOVER));
        checker.addDepositCap(1_100_000 * 1e6);
        // total deposit cap over
        vm.prank(alice);
        checker.addDepositCap(500_000 * 1e6);
        vm.expectRevert(bytes(ErrorsV1.CAPOVER));
        checker.addDepositCap(600_000 * 1e6);
        //deposit cap over twice
        vm.expectRevert(bytes(ErrorsV1.CAPOVER));
        vm.prank(alice);
        checker.addDepositCap(600_000 * 1e6);
    }

    function test_addDeposit_Success() public {
        //assert token1 balance in checker
        checker.addDepositCap(800_000 * 1e6);
        vm.prank(alice);
        checker.addDepositCap(100_000 * 1e6);
        (uint256 _assets, uint40 _timestamp) = checker.deposits(address(this));
        assertEq(_assets, 800_000 * 1e6);
        assertEq(_timestamp, uint40(block.timestamp));
        (uint256 _assets1, ) = checker.deposits(alice);
        assertEq(_assets1, 100_000 * 1e6);
        //total
        assertEq(checker.totalDeposits(), 900_000 * 1e6);
    }

    function test_reduceDepositCap_Success1() public {
        checker.addDepositCap(800_000 * 1e6);
        skip(8 days);
        checker.reduceDepositCap(400_000 * 1e6);
        (uint256 _assets, ) = checker.deposits(address(this));
        assertEq(_assets, 400_000 * 1e6);
        //total
        assertEq(checker.totalDeposits(), 400_000 * 1e6);
    }

    function test_reduceDepositCap_Success2() public {
        checker.addDepositCap(800_000 * 1e6);
        skip(8 days);
        checker.reduceDepositCap(900_000 * 1e6);
        (uint256 _assets, ) = checker.deposits(address(this));
        assertEq(_assets, 0);
        //total
        assertEq(checker.totalDeposits(), 0);
    }
}

contract OrangeValidationCheckerMock is OrangeValidationChecker {
    constructor(address _params) OrangeERC20("OrangeStrategyImplV1", "OrangeStrategyImplV1") {
        params = OrangeParametersV1(_params);
    }

    function execAllowlisted(bytes32[] calldata _merkleProof) external view Allowlisted(_merkleProof) returns (bool) {
        return true;
    }

    function addDepositCap(uint256 _assets) external {
        super._addDepositCap(_assets);
    }

    function reduceDepositCap(uint256 _assets) external {
        super._reduceDepositCap(_assets);
    }
}
