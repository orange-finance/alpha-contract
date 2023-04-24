// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";
import {OrangeAlphaParameters, GelatoOps} from "../../../contracts/core/OrangeAlphaParameters.sol";

contract OrangeAlphaParametersTest is BaseTest {
    OrangeAlphaParameters params;

    function setUp() public {
        //deploy parameters
        params = new OrangeAlphaParameters();
    }

    /* ========== CONSTRUCTOR ========== */
    function test_constructor_Success() public {
        assertEq(params.depositCap(), 100_000 * 1e6);
        assertEq(params.totalDepositCap(), 100_000 * 1e6);
        assertEq(params.minDepositAmount(), 100 * 1e6);
        assertEq(params.slippageBPS(), 500);
        assertEq(params.tickSlippageBPS(), 10);
        assertEq(params.twapSlippageInterval(), 5 minutes);
        assertEq(params.maxLtv(), 80000000);
        assertEq(params.lockupPeriod(), 0);
        assertEq(params.strategists(address(this)), true);
        assertEq(params.allowlistEnabled(), true);
        assertEq(params.gelatoExecutor(), GelatoOps.getDedicatedMsgSender(address(this)));
    }

    function test_onlyOwner() public {
        vm.startPrank(alice);
        vm.expectRevert("Ownable");
        params.setDepositCap(1, 1);
        vm.expectRevert("Ownable");
        params.setMinDepositAmount(1);
        vm.expectRevert("Ownable");
        params.setSlippage(1, 1);
        vm.expectRevert("Ownable");
        params.setTwapSlippageInterval(1);
        vm.expectRevert("Ownable");
        params.setMaxLtv(1);
        vm.expectRevert("Ownable");
        params.setLockupPeriod(1);
        vm.expectRevert("Ownable");
        params.setStrategist(address(this), true);
        vm.expectRevert("Ownable");
        params.setAllowlistEnabled(true);
        vm.expectRevert("Ownable");
        params.setMerkleRoot(0x0);
        vm.expectRevert("Ownable");
        params.setGelato(address(this));
        vm.expectRevert("Ownable");
        params.setPeriphery(address(this));
    }

    function test_Success() public {
        params.setDepositCap(1, 1);
        assertEq(params.depositCap(), 1);
        assertEq(params.totalDepositCap(), 1);

        params.setMinDepositAmount(1);
        assertEq(params.minDepositAmount(), 1);

        params.setSlippage(1, 1);
        assertEq(params.slippageBPS(), 1);
        assertEq(params.tickSlippageBPS(), 1);

        params.setTwapSlippageInterval(1);
        assertEq(params.twapSlippageInterval(), 1);

        params.setMaxLtv(1);
        assertEq(params.maxLtv(), 1);

        params.setLockupPeriod(1);
        assertEq(params.lockupPeriod(), 1);

        params.setStrategist(alice, true);
        assertEq(params.strategists(alice), true);

        params.setAllowlistEnabled(true);
        assertEq(params.allowlistEnabled(), true);

        params.setMerkleRoot(0x0);
        assertEq(params.merkleRoot(), 0x0);

        params.setGelato(alice);
        assertEq(params.gelatoExecutor(), GelatoOps.getDedicatedMsgSender(alice));

        params.setPeriphery(address(this));
        assertEq(params.periphery(), address(this));
    }
}
