// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import {OrangeParametersV1, ErrorsV1} from "../../../contracts/coreV1/OrangeParametersV1.sol";

contract OrangeParametersV1Test is BaseTest {
    OrangeParametersV1 params;

    function setUp() public {
        //deploy parameters
        params = new OrangeParametersV1();
    }

    /* ========== CONSTRUCTOR ========== */
    function test_constructor_Success() public {
        assertEq(params.slippageBPS(), 500);
        assertEq(params.tickSlippageBPS(), 10);
        assertEq(params.twapSlippageInterval(), 5 minutes);
        assertEq(params.maxLtv(), 80000000);
        assertEq(params.allowlistEnabled(), true);
    }

    function test_onlyOwner_Revert() public {
        vm.startPrank(alice);
        vm.expectRevert("Ownable");
        params.setSlippage(1, 1);
        vm.expectRevert("Ownable");
        params.setTwapSlippageInterval(1);
        vm.expectRevert("Ownable");
        params.setMaxLtv(1);
        vm.expectRevert("Ownable");
        params.setAllowlistEnabled(true);
        vm.expectRevert("Ownable");
        params.setMerkleRoot(0x0);
        vm.expectRevert("Ownable");
        params.setDepositCap(1, 1);
        vm.expectRevert("Ownable");
        params.setMinDepositAmount(1);
        vm.expectRevert("Ownable");
        params.setHelper(address(this));
        vm.expectRevert("Ownable");
        params.setStrategyImpl(address(this));
    }

    function test_validation_Revert() public {
        vm.expectRevert(bytes(ErrorsV1.INVALID_PARAM));
        params.setSlippage(10001, 1);
        vm.expectRevert(bytes(ErrorsV1.INVALID_PARAM));
        params.setMaxLtv(100000001);
        vm.expectRevert(bytes(ErrorsV1.INVALID_PARAM));
        params.setDepositCap(1, 0);
    }

    function test_Success() public {
        params.setSlippage(1, 1);
        assertEq(params.slippageBPS(), 1);
        assertEq(params.tickSlippageBPS(), 1);

        params.setTwapSlippageInterval(1);
        assertEq(params.twapSlippageInterval(), 1);

        params.setMaxLtv(1);
        assertEq(params.maxLtv(), 1);

        params.setAllowlistEnabled(true);
        assertEq(params.allowlistEnabled(), true);

        params.setMerkleRoot(0x0);
        assertEq(params.merkleRoot(), 0x0);

        params.setDepositCap(1, 1);
        assertEq(params.depositCap(), 1);
        assertEq(params.totalDepositCap(), 1);

        params.setMinDepositAmount(1);
        assertEq(params.minDepositAmount(), 1);

        params.setHelper(alice);
        assertEq(params.helper(), alice);

        params.setStrategyImpl(address(this));
        assertEq(params.strategyImpl(), address(this));
    }
}
