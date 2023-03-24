// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../core/OrangeAlphaTestBase.sol";

contract OrangeAlphaVaultScenarioTest is OrangeAlphaTestBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    IOrangeAlphaVault.Ticks _ticks;

    // currentTick = -204714;

    uint256 constant HEDGE_RATIO = 100e6; //100%
    uint32 constant MAX_LTV = 70000000;

    function setUp() public override {
        super.setUp();

        params.setMaxLtv(MAX_LTV);
        _ticks.currentTick = currentTick;
        _ticks.lowerTick = lowerTick;
        _ticks.upperTick = upperTick;

        //rebalance (set ticks)
        vault.rebalance(lowerTick, upperTick, stoplossLowerTick, stoplossUpperTick, HEDGE_RATIO, 0);

        //deal
        deal(address(token1), address(11), 10_000 * 1e6);
        deal(address(token1), address(12), 10_000 * 1e6);
        deal(address(token1), address(13), 10_000 * 1e6);
        deal(address(token1), address(14), 10_000 * 1e6);
        deal(address(token1), address(15), 10_000 * 1e6);

        deal(address(token0), carol, 1000 ether);
        deal(address(token1), carol, 100_000 * 1e6);

        //approve
        vm.prank(address(11));
        token1.approve(address(vault), type(uint256).max);
        vm.prank(address(12));
        token1.approve(address(vault), type(uint256).max);
        vm.prank(address(13));
        token1.approve(address(vault), type(uint256).max);
        vm.prank(address(14));
        token1.approve(address(vault), type(uint256).max);
        vm.prank(address(15));
        token1.approve(address(vault), type(uint256).max);
    }

    // function test_scenario1() public {
    //     //deposit

    //     uint256 _shares1 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(11));
    //     vault.deposit(10_000 * 1e6, _shares1, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares2 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(12));
    //     vault.deposit(10_000 * 1e6, _shares2, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares3 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(13));
    //     vault.deposit(10_000 * 1e6, _shares3, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares4 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(14));
    //     vault.deposit(10_000 * 1e6, _shares4, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares5 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(15));
    //     vault.deposit(10_000 * 1e6, _shares5, new bytes32[](0));

    //     skip(8 days);

    //     //swap
    //     multiSwapByCarol(10 ether, 12_000 * 1e6, 100);

    //     //redeem
    //     redeem(address(11));
    //     skip(1);
    //     redeem(address(12));
    //     skip(1);
    //     redeem(address(13));
    //     skip(1);
    //     redeem(address(14));
    //     skip(1);
    //     redeem(address(15));

    //     (, int24 _tick, , , , , ) = pool.slot0();
    //     console2.log(_tick.toString(), "afterTick");
    // }

    // function test_scenario2() public {
    //     consoleRate();

    //     //deposit
    //     uint256 _shares1 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(11));
    //     vault.deposit(10_000 * 1e6, _shares1, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares2 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(12));
    //     vault.deposit(10_000 * 1e6, _shares2, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares3 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(13));
    //     vault.deposit(10_000 * 1e6, _shares3, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares4 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(14));
    //     vault.deposit(10_000 * 1e6, _shares4, new bytes32[](0));
    //     skip(1);
    //     uint256 _shares5 = (vault.convertToShares(10_000 * 1e6) * 9900) / MAGIC_SCALE_1E4;
    //     vm.prank(address(15));
    //     vault.deposit(10_000 * 1e6, _shares5, new bytes32[](0));

    //     skip(8 days);

    //     //swap
    //     multiSwapByCarol(10 ether, 12_000 * 1e6, 100);

    //     //range out
    //     swapByCarol(true, 640 ether);
    //     skip(1 days);
    //     (, int24 __tick, , , , , ) = pool.slot0();
    //     console2.log(__tick.toString(), "middleTick");

    //     //stoploss
    //     vault.rebalance(lowerTick, upperTick, lowerTick, upperTick, 1);
    //     // vm.prank(vault.dedicatedMsgSender());
    //     vault.stoploss(__tick);
    //     skip(1 days);

    //     //rebalance
    //     int24 _newLowerTick = -207600;
    //     int24 _newUpperTick = -205560;
    //     // (, int24 ___tick, , , , , ) = pool.slot0();
    //     skip(1 days);
    //     vault.rebalance(_newLowerTick, _newUpperTick, _newLowerTick, _newUpperTick, 2359131680723000);
    //     skip(1 days);

    //     //swap
    //     multiSwapByCarol(10 ether, 12_000 * 1e6, 100);

    //     //redeem
    //     redeem(address(11));
    //     skip(1);
    //     redeem(address(12));
    //     skip(1);
    //     redeem(address(13));
    //     skip(1);
    //     redeem(address(14));
    //     skip(1);
    //     redeem(address(15));

    //     (, int24 _tick, , , , , ) = pool.slot0();
    //     console2.log(_tick.toString(), "afterTick");
    // }

    // /* ========== TEST functions ========== */
    // function redeem(address _user) private {
    //     uint256 _share11 = vault.balanceOf(_user);
    //     vm.prank(_user);
    //     vault.redeem(_share11, _user, address(0), 9_600 * 1e6);
    //     console2.log(token1.balanceOf(_user), _user);
    // }

    // function consoleRate() private view {
    //     (, int24 _tick, , , , , ) = pool.slot0();
    //     uint256 rate0 = OracleLibrary.getQuoteAtTick(_tick, 1 ether, address(token0), address(token1));
    //     console2.log(rate0, "rate");
    // }
}
