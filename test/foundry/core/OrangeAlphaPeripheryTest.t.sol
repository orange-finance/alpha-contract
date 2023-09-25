// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorsAlpha} from "../../../contracts/core/ErrorsAlpha.sol";
import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";
import {OrangeAlphaParameters} from "../../../contracts/core/OrangeAlphaParameters.sol";
import {OrangeAlphaPeriphery} from "../../../contracts/core/OrangeAlphaPeriphery.sol";

contract OrangeAlphaPeripheryTest is BaseTest {
    using SafeERC20 for IERC20;
    using Ints for int24;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    OrangeAlphaPeripheryMock periphery;
    OrangeAlphaVaultMockForPeriphery vault;
    OrangeAlphaParameters params;
    IUniswapV3Pool pool;
    IERC20 token1;

    //parameters
    uint256 constant DEPOSIT_CAP = 1_000_000 * 1e6;
    uint256 constant TOTAL_DEPOSIT_CAP = 1_000_000 * 1e6;
    uint32 constant LOCKUP_PERIOD = 7 days;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        //deploy parameters
        params = new OrangeAlphaParameters();

        //deploy vault
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        token1 = IERC20(tokenAddr.usdcAddr);
        vault = new OrangeAlphaVaultMockForPeriphery(address(token1), address(pool));

        //deploy periphery
        periphery = new OrangeAlphaPeripheryMock(address(vault), address(params));

        //set parameters
        params.setDepositCap(DEPOSIT_CAP, TOTAL_DEPOSIT_CAP);
        params.setLockupPeriod(LOCKUP_PERIOD);
        params.setAllowlistEnabled(false); //merkle allow list off

        //deal
        deal(address(token1), address(this), 100_000_000 * 1e6);
        deal(address(token1), alice, 100_000_000 * 1e6);

        //approve
        token1.approve(address(periphery), type(uint256).max);
        vm.startPrank(alice);
        token1.approve(address(periphery), type(uint256).max);
        vm.stopPrank();
    }

    /* ========== CONSTRUCTOR ========== */
    function test_constructor_Success() public {
        assertEq(address(periphery.vault()), address(vault));
        assertEq(address(periphery.params()), address(params));
    }

    /* ========== FUNCTIONS ========== */
    function test_deposit_Revert1() public {
        //deposit cap over
        vm.expectRevert(bytes(ErrorsAlpha.CAPOVER));
        periphery.deposit(1_100_000 * 1e6, 1_100_000 * 1e6, new bytes32[](0));
        // total deposit cap over
        vm.prank(alice);
        periphery.deposit(500_000 * 1e6, 500_000 * 1e6, new bytes32[](0));
        vm.expectRevert(bytes(ErrorsAlpha.CAPOVER));
        periphery.deposit(600_000 * 1e6, 600_000 * 1e6, new bytes32[](0));
        //deposit cap over twice
        vm.expectRevert(bytes(ErrorsAlpha.CAPOVER));
        vm.prank(alice);
        periphery.deposit(600_000 * 1e6, 600_000 * 1e6, new bytes32[](0));
    }

    function test_deposit_Success() public {
        //assert token1 balance in periphery
        periphery.deposit(800_000 * 1e6, 800_000 * 1e6, new bytes32[](0));
        assertEq(token1.balanceOf(address(vault)), 800_000 * 1e6);
    }

    function test_redeem_Revert1() public {
        //lockup
        periphery.deposit(800_000 * 1e6, 800_000 * 1e6, new bytes32[](0));
        vm.expectRevert(bytes(ErrorsAlpha.LOCKUP));
        periphery.redeem(800_000 * 1e6, 0);
    }

    function test_redeem_Success1() public {
        periphery.deposit(800_000 * 1e6, 800_000 * 1e6, new bytes32[](0));
        skip(8 days);
        periphery.redeem(400_000 * 1e6, 400_000 * 1e6);
        (uint256 _assets, ) = periphery.deposits(address(this));
        assertEq(_assets, 400_000 * 1e6);
        assertEq(periphery.totalDeposits(), 400_000 * 1e6);
    }

    function test_redeem_Success2() public {
        //deposit < assets
        periphery.deposit(800_000 * 1e6, 800_000 * 1e6, new bytes32[](0));
        skip(8 days);
        periphery.redeem(800_000 * 1e6, 800_000 * 1e6);
        (uint256 _assets, ) = periphery.deposits(address(this));
        assertEq(_assets, 0);
        assertEq(periphery.totalDeposits(), 0);
    }
}

contract OrangeAlphaPeripheryMock is OrangeAlphaPeriphery {
    constructor(address _vault, address _params) OrangeAlphaPeriphery(_vault, _params) {}

    function _validateSenderAllowlisted(address, bytes32[] calldata) internal view override {
        //merkle proof is tested in hardhat tests by typescripts
    }
}

contract OrangeAlphaVaultMockForPeriphery {
    IERC20 public token1;
    IUniswapV3Pool public pool;

    constructor(address _token1, address _pool) {
        token1 = IERC20(_token1);
        pool = IUniswapV3Pool(_pool);
    }

    function deposit(uint256 _shares, address, uint256 _maxAssets) external returns (uint256) {
        token1.transferFrom(msg.sender, address(this), _maxAssets);
        return _shares;
    }

    function redeem(uint256, address, address owner, uint256 minAssets) external returns (uint256) {
        token1.transfer(owner, minAssets);
        return minAssets;
    }
}
