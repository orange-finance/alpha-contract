// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {OrangeAlphaPeripheryMock} from "../../../contracts/mocks/OrangeAlphaPeripheryMock.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOrangeAlphaVault} from "../../../contracts/interfaces/IOrangeAlphaVault.sol";
import {OrangeAlphaParameters} from "../../../contracts/core/OrangeAlphaParameters.sol";

contract OrangeAlphaPeripheryTest is BaseTest {
    using SafeERC20 for IERC20;
    using Ints for int24;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    OrangeAlphaPeripheryMock periphery;
    OrangeAlphaVaultMockForPeriphery vault;
    OrangeAlphaParameters params;
    IUniswapV3Pool pool;
    IERC20 weth;
    IERC20 usdc;

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
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);
        vault = new OrangeAlphaVaultMockForPeriphery(
            address(usdc),
            address(pool)
        );

        //deploy periphery
        periphery = new OrangeAlphaPeripheryMock(
            address(vault),
            address(params)
        );

        //set parameters
        params.setDepositCap(DEPOSIT_CAP, TOTAL_DEPOSIT_CAP);
        params.setLockupPeriod(LOCKUP_PERIOD);
        params.setAllowlistEnabled(false); //merkle allow list off

        //deal
        deal(tokenAddr.usdcAddr, address(this), 10_000_000 * 1e6);
        deal(tokenAddr.usdcAddr, alice, 10_000_000 * 1e6);

        //approve
        usdc.approve(address(periphery), type(uint256).max);
        vm.startPrank(alice);
        usdc.approve(address(periphery), type(uint256).max);
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
        vm.expectRevert("CAPOVER");
        periphery.deposit(1_100_000 * 1e6, 100, new bytes32[](0));
        //total deposit cap over
        vm.prank(alice);
        periphery.deposit(500_000 * 1e6, 100, new bytes32[](0));
        vm.expectRevert("CAPOVER");
        periphery.deposit(600_000 * 1e6, 100, new bytes32[](0));
        //deposit cap over twice
        vm.expectRevert("CAPOVER");
        vm.prank(alice);
        periphery.deposit(600_000 * 1e6, 100, new bytes32[](0));
    }

    function test_deposit_Success() public {
        //assert USDC balance in periphery
        periphery.deposit(800_000 * 1e6, 100, new bytes32[](0));
        assertEq(usdc.balanceOf(address(periphery)), 800_000 * 1e6);
    }

    function test_redeem_Revert1() public {
        //lockup
        periphery.deposit(800_000 * 1e6, 100, new bytes32[](0));
        vm.expectRevert("LOCKUP");
        periphery.redeem(800_000 * 1e6, 0);
    }

    function test_redeem_Success1() public {
        periphery.deposit(800_000 * 1e6, 100, new bytes32[](0));
        skip(8 days);
        periphery.redeem(400_000 * 1e6, 400_000 * 1e6);
        (uint256 _assets, ) = periphery.deposits(address(this));
        assertEq(_assets, 400_000 * 1e6);
        assertEq(periphery.totalDeposits(), 400_000 * 1e6);
    }

    function test_redeem_Success2() public {
        //deposit < assets
        periphery.deposit(800_000 * 1e6, 100, new bytes32[](0));
        skip(8 days);
        periphery.redeem(400_000 * 1e6, 810_000 * 1e6);
        (uint256 _assets, ) = periphery.deposits(address(this));
        assertEq(_assets, 0);
        assertEq(periphery.totalDeposits(), 0);
    }

    function test_checker_Success1() public {
        (, int24 _currentTick, , , , , ) = pool.slot0();
        int24 _twap = periphery.getTwap();
        console2.log("currentTick", _currentTick.toString());
        console2.log("twap", _twap.toString());

        //currentTick -204714
        //in range
        vault.setStoplossTicks(-206280, -203160);
        (bool canExec, bytes memory execPayload) = periphery.checker();
        assertEq(canExec, false);

        //out of range
        vault.setStoplossTicks(-200000, -190000);
        (canExec, execPayload) = periphery.checker();
        assertEq(canExec, true);
    }

    function test_checker_Success2() public {
        //current is in and twap is out
        vault.setStoplossTicks(-206280, -203160);
        periphery.setTwap(-200000);
        (bool canExec, bytes memory execPayload) = periphery.checker();
        assertEq(canExec, false);

        //current is out and twap is in
        vault.setStoplossTicks(-200000, -190000);
        periphery.setTwap(-195000);
        (canExec, execPayload) = periphery.checker();
        assertEq(canExec, false);
    }
}

contract OrangeAlphaVaultMockForPeriphery is IOrangeAlphaVault {
    IERC20 public token1;
    IUniswapV3Pool public pool;
    int24 public override stoplossLowerTick;
    int24 public override stoplossUpperTick;

    constructor(address _token1, address _pool) {
        token1 = IERC20(_token1);
        pool = IUniswapV3Pool(_pool);
    }

    function setStoplossTicks(
        int24 _stoplossLowerTick,
        int24 _stoplossUpperTick
    ) external {
        stoplossLowerTick = _stoplossLowerTick;
        stoplossUpperTick = _stoplossUpperTick;
    }

    function totalAssets() external view returns (uint256 totalManagedAssets) {
        return 0;
    }

    /**
     * @notice convert assets to shares(shares is the amount of vault token)
     * @param assets amount of assets
     * @return shares
     */
    function convertToShares(uint256 assets)
        external
        view
        returns (uint256 shares)
    {
        return 0;
    }

    /**
     * @notice convert shares to assets
     * @param shares amount of vault token
     * @return assets
     */
    function convertToAssets(uint256 shares)
        external
        view
        returns (uint256 assets)
    {
        return 0;
    }

    /**
     * @notice get underlying assets
     * @return underlyingAssets amount0Current, amount1Current, accruedFees0, accruedFees1, amount0Balance, amount1Balance
     */
    function getUnderlyingBalances()
        external
        view
        returns (UnderlyingAssets memory underlyingAssets)
    {
        return UnderlyingAssets(0, 0, 0, 0, 0, 0);
    }

    /**
     * @notice get simuldated liquidity if rebalanced
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _newStoplossLowerTick The new lower bound of the position's range
     * @param _newStoplossUpperTick The new upper bound of the position's range
     * @return liquidity_ amount of liquidity
     */
    function getRebalancedLiquidity(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick
    ) external view returns (uint128 liquidity_) {
        return 0;
    }

    /**
     * @notice whether can stoploss
     * @param _currentTick current tick
     * @param _lowerTick lower tick
     * @param _upperTick upper tick
     * @return bool whether can stoploss
     */
    function canStoploss(
        int24 _currentTick,
        int24 _lowerTick,
        int24 _upperTick
    ) external view returns (bool) {
        //is current tick out of range
        return _currentTick < _lowerTick || _currentTick > _upperTick;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    /**
     * @notice deposit assets and get vault token
     * @param assets amount of assets
     * @param _receiver receiver address
     * @param minShares minimum amount of returned vault token
     * @return shares
     */
    function deposit(
        uint256 assets,
        address _receiver,
        uint256 minShares
    ) external returns (uint256 shares) {
        return 0;
    }

    /**
     * @notice redeem vault token to assets
     * @param shares amount of vault token
     * @param receiver receiver address
     * @param owner owner address
     * @param minAssets minimum amount of returned assets
     * @return assets
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 minAssets
    ) external returns (uint256 assets) {
        return minAssets;
    }

    /**
     * @notice emit action event
     */
    function emitAction() external {
        return;
    }

    /**
     * @notice Remove all positions only when current price is out of range
     * @param inputTick Input tick for slippage checking
     */
    function stoploss(int24 inputTick) external {
        return;
    }

    /**
     * @notice Remove all positions
     * @param inputTick Input tick for slippage checking
     */
    function removeAllPosition(int24 inputTick) external {
        return;
    }

    /**
     * @notice Change the range of underlying UniswapV3 position
     * @param _newLowerTick The new lower bound of the position's range
     * @param _newUpperTick The new upper bound of the position's range
     * @param _newStoplossLowerTick The new lower bound of the stoploss range
     * @param _newStoplossUpperTick The new upper bound of the stoploss range
     * @param _minNewLiquidity minimum liqidiity
     */
    function rebalance(
        int24 _newLowerTick,
        int24 _newUpperTick,
        int24 _newStoplossLowerTick,
        int24 _newStoplossUpperTick,
        uint128 _minNewLiquidity
    ) external {
        return;
    }
}
