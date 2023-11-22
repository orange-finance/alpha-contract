// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@test/foundry/utils/BaseTest.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {DopexV2LiquidityPoolManager} from "../../../contracts/poolManager/DopexV2LiquidityPoolManager.sol";
import {TickMath} from "../../../contracts/libs/uniswap/TickMath.sol";
import {FullMath} from "../../../contracts/libs/uniswap/LiquidityAmounts.sol";

import {MockVault} from "./mocks/MockVault.sol";
import {IUniswapV3SingleTickLiquidityHandler} from "@src/vendor/dopexV2/IUniswapV3SingleTickLiquidityHandler.sol";

contract DopexV2LiquidityPoolManagerTest is BaseTest {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    address constant DOPEX_POSITION_MANAGER = 0xE4bA6740aF4c666325D49B3112E4758371386aDc;
    address constant DOPEX_UNISWAP_V3_HANDLER = 0xe11d346757d052214686bCbC860C94363AfB4a9A;
    address constant DOPEX_OWNER = 0x2c9bC901f39F847C2fe5D2D7AC9c5888A2Ab8Fcf;

    IUniswapV3Pool constant UNISWAP_WETH_USDCE_500 = IUniswapV3Pool(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);
    ISwapRouter constant UNISWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IERC20 constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    IERC20 constant USDCE = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    address mockVault;
    DopexV2LiquidityPoolManager manager;
    IERC721 public nft;

    int24 public lowerTick = -205680;
    int24 public upperTick = -203760;
    /// @dev tick at block 149490083
    /// @dev 1 WETH = 2043.708900 USDC.e
    int24 public currentTick = -200095;

    function setUp() public virtual {
        // start from the block where handler is deployed
        vm.createSelectFork("arb", 151299689);

        mockVault = address(new MockVault());
        MockVault(mockVault).setToken0(address(WETH));
        MockVault(mockVault).setToken1(address(USDCE));

        manager = new DopexV2LiquidityPoolManager({
            vault_: mockVault,
            pool_: address(UNISWAP_WETH_USDCE_500),
            positionManager_: DOPEX_POSITION_MANAGER,
            handler_: DOPEX_UNISWAP_V3_HANDLER
        });

        //set Ticks for testing
        (, int24 _tick, , , , , ) = UNISWAP_WETH_USDCE_500.slot0();
        currentTick = _tick;

        //deal
        deal(address(WETH), mockVault, 10_000 ether);
        deal(address(USDCE), mockVault, 10_000_000 * 1e6);
        deal(address(WETH), carol, 10_000 ether);
        deal(address(USDCE), carol, 10_000_000 * 1e6);

        //approve
        vm.startPrank(mockVault);
        WETH.approve(address(manager), type(uint256).max);
        USDCE.approve(address(manager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(carol);
        WETH.approve(address(UNISWAP_ROUTER), type(uint256).max);
        USDCE.approve(address(UNISWAP_ROUTER), type(uint256).max);
        vm.stopPrank();
    }

    function test_onlyOperator_Revert() public {
        vm.expectRevert(bytes("ONLY_VAULT"));
        vm.prank(alice);
        manager.mint(lowerTick, upperTick, 0);

        vm.expectRevert(bytes("ONLY_VAULT"));
        vm.prank(alice);
        manager.burnAndCollect(lowerTick, upperTick, 0);
    }

    function test_onlyOwner_Revert() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        manager.setPerfFeeRecipient(address(0));

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(alice);
        manager.setPerfFeeDivisor(0);
    }

    function test_constructor_Success() public {
        assertEq(manager.reversed(), false);
        MockVault _v = new MockVault();
        _v.setToken0(address(WETH));
        _v.setToken1(address(USDCE));

        DopexV2LiquidityPoolManager _m1 = new DopexV2LiquidityPoolManager({
            vault_: address(_v),
            pool_: address(UNISWAP_WETH_USDCE_500),
            positionManager_: DOPEX_POSITION_MANAGER,
            handler_: DOPEX_UNISWAP_V3_HANDLER
        });
        assertEq(_m1.reversed(), false);

        _v.setToken0(address(USDCE));
        _v.setToken1(address(WETH));

        DopexV2LiquidityPoolManager _m2 = new DopexV2LiquidityPoolManager({
            vault_: address(_v),
            pool_: address(UNISWAP_WETH_USDCE_500),
            positionManager_: DOPEX_POSITION_MANAGER,
            handler_: DOPEX_UNISWAP_V3_HANDLER
        });

        assertEq(_m2.reversed(), true);
    }

    function test_getTwap_Success() public {
        int24 _twap = manager.getTwap(5 minutes);
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = 5 minutes;
        secondsAgo[1] = 0;
        (int56[] memory tickCumulatives, ) = UNISWAP_WETH_USDCE_500.observe(secondsAgo);
        int24 avgTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(5 minutes)));
        assertEq(avgTick, _twap);
    }

    function test_validateTicks_Revert() public {
        vm.expectRevert(bytes("INVALID_TICKS"));
        manager.validateTicks(1, upperTick);
        vm.expectRevert(bytes("INVALID_TICKS"));
        manager.validateTicks(lowerTick, 1);
        vm.expectRevert(bytes("INVALID_TICKS"));
        manager.validateTicks(upperTick, lowerTick);
    }

    function test_burnAndCollect_ReturnsZero() public {
        manager.setPerfFeeRecipient(david);
        manager.setPerfFeeDivisor(20); // 5%

        (uint256 _burned0, uint256 _burned1) = manager.burnAndCollect(lowerTick, upperTick, 0);

        assertEq(_burned0, 0);
        assertEq(_burned1, 0);
    }

    function test_all_Success() public {
        // uint160 _ratio = currentTick.getSqrtRatioAtTick();

        // current tick:  -200491
        currentTick = manager.getCurrentTick();
        emit log_named_int("currentTick", currentTick);

        // price range ≈ $80
        lowerTick = -200690;
        upperTick = -200290;
        emit log_named_int("lowerTick", lowerTick);
        emit log_named_int("upperTick", upperTick);

        //compute liquidity
        uint128 _liquidity = manager.getLiquidityForAmounts(lowerTick, upperTick, 1 ether, 1000 * 1e6);

        //mint
        uint wethBefore = WETH.balanceOf(address(mockVault));
        uint usdceBefore = USDCE.balanceOf(address(mockVault));

        (uint _wethWillUsed, uint _usdceWillUsed) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        assertEq(_wethWillUsed, 1 ether, "manager.getAmountsForLiquidity: amount0 mismatch");
        assertEq(_usdceWillUsed, 1000 * 1e6, "manager.getAmountsForLiquidity: amount1 mismatch");

        vm.prank(mockVault);
        (uint _wethUsed, uint _usdceUsed) = manager.mint(lowerTick, upperTick, _liquidity);
        emit log_named_uint("wethWillUsed", _wethWillUsed);
        emit log_named_uint("usdceWillUsed", _usdceWillUsed);
        emit log_named_uint("wethUsed", _wethUsed);
        emit log_named_uint("usdceUsed", _usdceUsed);

        assertEq(_wethUsed, _wethWillUsed, "manager.mint: amount0 mismatch");
        assertEq(_usdceUsed, _usdceWillUsed, "manager.mint: amount1 mismatch");

        uint wethAfter = WETH.balanceOf(address(mockVault));
        uint usdceAfter = USDCE.balanceOf(address(mockVault));

        assertEq(wethBefore - wethAfter, _wethUsed, "manager.mint: balance0 used mismatch");
        assertEq(usdceBefore - usdceAfter, _usdceUsed, "manager.mint: balance1 used mismatch");

        uint128 _currentLiquidity = manager.getCurrentLiquidity(lowerTick, upperTick);
        emit log_named_uint("currentLiquidity", _currentLiquidity);
        assertEq(_currentLiquidity, _liquidity);
        // //swap
        // multiSwapByCarol();

        // //compute current fee and position
        // (uint256 fee0, uint256 fee1) = manager.getFeesEarned(lowerTick, upperTick);
        // console2.log(fee0, fee1);
        // (_amount0, _amount1) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        // uint _balance0 = WETH.balanceOf(address(this));
        // uint _balance1 = USDCE.balanceOf(address(this));

        // // burn and collect
        // vm.prank(mockVault);
        // (uint burn0_, uint burn1_) = manager.burnAndCollect(lowerTick, upperTick, _liquidity);
        // assertEq(_amount0, burn0_);
        // assertEq(_amount1, burn1_);

        // assertEq(_balance0 + fee0 + burn0_, WETH.balanceOf(address(this)));
        // assertEq(_balance1 + fee1 + burn1_, USDCE.balanceOf(address(this)));
        // // // _consoleBalance();
    }

    function test_allWithPerfFee_Success() public {
        manager.setPerfFeeRecipient(david);
        manager.setPerfFeeDivisor(20); // 5%

        //compute liquidity
        uint128 _liquidity = manager.getLiquidityForAmounts(lowerTick, upperTick, 1 ether, 1000 * 1e6);

        //mint
        (uint _amount0, uint _amount1) = manager.mint(lowerTick, upperTick, _liquidity);

        //assertion of mint
        (uint _amount0_, uint _amount1_) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, _amount0_ + 1);
        assertEq(_amount1, _amount1_ + 1);

        uint128 _liquidity2 = manager.getCurrentLiquidity(lowerTick, upperTick);
        assertEq(_liquidity, _liquidity2);

        //swap
        multiSwapByCarol();

        //compute current fee and position
        (uint256 fee0, uint256 fee1) = manager.getFeesEarned(lowerTick, upperTick);
        (_amount0, _amount1) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        uint _balance0 = WETH.balanceOf(address(this));
        uint _balance1 = USDCE.balanceOf(address(this));

        // burn and collect
        (uint burn0_, uint burn1_) = manager.burnAndCollect(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, burn0_);
        assertEq(_amount1, burn1_);

        // 5% of fee
        (uint _perfFee0, uint _perfFee1) = (fee0 / 20, fee1 / 20);

        assertEq(WETH.balanceOf(david), _perfFee0);
        assertEq(USDCE.balanceOf(david), _perfFee1);
        assertEq(WETH.balanceOf(address(this)), _balance0 + fee0 - _perfFee0 + burn0_);
        assertEq(USDCE.balanceOf(address(this)), _balance1 + fee1 - _perfFee1 + burn1_);
    }

    function test_allWithZeroFee_Success() public {
        manager.setPerfFeeRecipient(david);
        manager.setPerfFeeDivisor(0); // no performance fee

        //compute liquidity
        uint128 _liquidity = manager.getLiquidityForAmounts(lowerTick, upperTick, 1 ether, 1000 * 1e6);

        //mint
        (uint _amount0, uint _amount1) = manager.mint(lowerTick, upperTick, _liquidity);

        //assertion of mint
        (uint _amount0_, uint _amount1_) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, _amount0_ + 1);
        assertEq(_amount1, _amount1_ + 1);

        uint128 _liquidity2 = manager.getCurrentLiquidity(lowerTick, upperTick);
        assertEq(_liquidity, _liquidity2);

        //swap
        multiSwapByCarol();

        //compute current fee and position
        (uint256 fee0, uint256 fee1) = manager.getFeesEarned(lowerTick, upperTick);
        (_amount0, _amount1) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        uint _balance0 = WETH.balanceOf(address(this));
        uint _balance1 = USDCE.balanceOf(address(this));

        // burn and collect
        (uint burn0_, uint burn1_) = manager.burnAndCollect(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, burn0_);
        assertEq(_amount1, burn1_);

        assertEq(WETH.balanceOf(david), 0);
        assertEq(USDCE.balanceOf(david), 0);
        assertEq(WETH.balanceOf(address(this)), _balance0 + fee0 + burn0_);
        assertEq(USDCE.balanceOf(address(this)), _balance1 + fee1 + burn1_);
    }

    function test_allReverse_Success() public {
        //re-deploy contract with reversed pair
        MockVault _v = new MockVault();
        _v.setToken0(address(USDCE));
        _v.setToken1(address(WETH));

        manager = new DopexV2LiquidityPoolManager({
            vault_: address(_v),
            pool_: address(UNISWAP_WETH_USDCE_500),
            positionManager_: DOPEX_POSITION_MANAGER,
            handler_: DOPEX_UNISWAP_V3_HANDLER
        });

        WETH.approve(address(manager), type(uint256).max);
        USDCE.approve(address(manager), type(uint256).max);

        // _consoleBalance();

        //compute liquidity
        uint128 _liquidity = manager.getLiquidityForAmounts(lowerTick, upperTick, 1000 * 1e6, 1 ether);

        //mint
        (uint _amount0, uint _amount1) = manager.mint(lowerTick, upperTick, _liquidity);
        console2.log(_amount0, _amount1);

        //assertion of mint
        (uint _amount0_, uint _amount1_) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, _amount0_ + 1);
        assertEq(_amount1, _amount1_ + 1);

        uint128 _liquidity2 = manager.getCurrentLiquidity(lowerTick, upperTick);
        console2.log(_liquidity2, "liquidity2");
        assertEq(_liquidity, _liquidity2);
        // _consoleBalance();

        //swap
        multiSwapByCarol();

        //compute current fee and position
        (uint256 fee0, uint256 fee1) = manager.getFeesEarned(lowerTick, upperTick);
        console2.log(fee0, fee1);
        (_amount0, _amount1) = manager.getAmountsForLiquidity(lowerTick, upperTick, _liquidity);
        uint _balance0 = USDCE.balanceOf(address(this));
        uint _balance1 = WETH.balanceOf(address(this));

        // burn and collect
        (uint burn0_, uint burn1_) = manager.burnAndCollect(lowerTick, upperTick, _liquidity);
        assertEq(_amount0, burn0_);
        assertEq(_amount1, burn1_);
        // _consoleBalance();

        assertEq(_balance0 + fee0 + burn0_, USDCE.balanceOf(address(this)));
        assertEq(_balance1 + fee1 + burn1_, WETH.balanceOf(address(this)));
        // _consoleBalance();
    }

    /* ========== TEST functions ========== */
    function swapByCarol(bool _zeroForOne, uint256 _amountIn) internal returns (uint256 amountOut_) {
        ISwapRouter.ExactInputSingleParams memory inputParams;
        if (_zeroForOne) {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(WETH),
                tokenOut: address(USDCE),
                fee: UNISWAP_WETH_USDCE_500.fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        } else {
            inputParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: address(USDCE),
                tokenOut: address(WETH),
                fee: UNISWAP_WETH_USDCE_500.fee(),
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        }
        vm.prank(carol);
        amountOut_ = UNISWAP_ROUTER.exactInputSingle(inputParams);
    }

    function multiSwapByCarol() internal {
        swapByCarol(true, 1 ether);
        swapByCarol(false, 2000 * 1e6);
        swapByCarol(true, 1 ether);
    }

    function _consoleBalance() internal view {
        console2.log("balances: ");
        console2.log(
            WETH.balanceOf(address(this)),
            USDCE.balanceOf(address(this)),
            WETH.balanceOf(address(manager)),
            USDCE.balanceOf(address(manager))
        );
    }
}
