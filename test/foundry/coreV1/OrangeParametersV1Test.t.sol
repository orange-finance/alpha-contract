// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import {OrangeParametersV1, ErrorsV1} from "../../../contracts/coreV1/OrangeParametersV1.sol";

contract OrangeParametersV1Test is BaseTest {
    OrangeParametersV1 params;

    event SetSlippage(uint16 slippageBPS, uint24 tickSlippageBPS);
    event SetTwapSlippageInterval(uint32 twapSlippageInterval);
    event SetMaxLtv(uint32 maxLtv);
    event SetAllowlistEnabled(bool allowlistEnabled);
    event SetMerkleRoot(bytes32 merkleRoot);
    event SetDepositCap(uint256 depositCap);
    event SetMinDepositAmount(uint256 minDepositAmount);
    event SetHelper(address helper);
    event SetStrategyImpl(address strategyImpl);

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
        params.setDepositCap(1);
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
    }

    function test_Success() public {
        vm.expectEmit(true, true, true, true);
        emit SetSlippage(1, 1);
        params.setSlippage(1, 1);
        assertEq(params.slippageBPS(), 1);
        assertEq(params.tickSlippageBPS(), 1);

        vm.expectEmit(true, true, true, true);
        emit SetTwapSlippageInterval(1);
        params.setTwapSlippageInterval(1);
        assertEq(params.twapSlippageInterval(), 1);

        vm.expectEmit(true, true, true, true);
        emit SetMaxLtv(1);
        params.setMaxLtv(1);
        assertEq(params.maxLtv(), 1);

        vm.expectEmit(true, true, true, true);
        emit SetAllowlistEnabled(true);
        params.setAllowlistEnabled(true);
        assertEq(params.allowlistEnabled(), true);

        vm.expectEmit(true, true, true, true);
        emit SetMerkleRoot(0x0);
        params.setMerkleRoot(0x0);
        assertEq(params.merkleRoot(), 0x0);

        vm.expectEmit(true, true, true, true);
        emit SetDepositCap(1);
        params.setDepositCap(1);
        assertEq(params.depositCap(), 1);

        vm.expectEmit(true, true, true, true);
        emit SetMinDepositAmount(1);
        params.setMinDepositAmount(1);
        assertEq(params.minDepositAmount(), 1);

        vm.expectEmit(true, true, true, true);
        emit SetHelper(alice);
        params.setHelper(alice);
        assertEq(params.helper(), alice);

        vm.expectEmit(true, true, true, true);
        emit SetStrategyImpl(address(this));
        params.setStrategyImpl(address(this));
        assertEq(params.strategyImpl(), address(this));
    }
}
