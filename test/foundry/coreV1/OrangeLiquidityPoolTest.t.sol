// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./OrangeVaultV1TestBase.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract OrangeLiquidityPoolTest is OrangeVaultV1TestBase {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    IERC721 public nft;

    function setUp() public virtual override {
        console2.log(address(this), "testcontract address");
        console2.log(msg.sender, "tester address");

        super.setUp();
        token0.approve(address(liquidityPool), type(uint256).max);
        token1.approve(address(liquidityPool), type(uint256).max);
        (, , uniswapAddr) = AddressHelper.addresses(block.chainid);
    }

    function _consoleBalance() internal view {
        console2.log("balances: ");
        console2.log(
            token0.balanceOf(address(this)),
            token1.balanceOf(address(this)),
            token0.balanceOf(address(liquidityPool)),
            token1.balanceOf(address(liquidityPool))
        );
    }

    function test_mint_Success() public {
        _consoleBalance();

        //compute liquidity
        IOrangeLiquidityPool.ParamsOfAmount memory _paramsA = IOrangeLiquidityPool.ParamsOfAmount(
            address(token0),
            address(token1),
            lowerTick,
            upperTick,
            1 ether,
            1000 * 1e6
        );
        uint128 _liquidity = liquidityPool.getLiquidityForAmounts(_paramsA);

        //mint
        IOrangeLiquidityPool.MintParams memory _mintParams = IOrangeLiquidityPool.MintParams(
            address(token0),
            address(token1),
            address(this),
            lowerTick,
            upperTick,
            _liquidity
        );
        (uint _amount0, uint _amount1) = liquidityPool.mint(_mintParams);
        console2.log(_amount0, _amount1);

        //assertion of mint
        IOrangeLiquidityPool.ParamsOfLiquidity memory _paramsB = IOrangeLiquidityPool.ParamsOfLiquidity(
            address(token0),
            address(token1),
            lowerTick,
            upperTick,
            _liquidity
        );
        (uint _amount0_, uint _amount1_) = liquidityPool.getAmountsForLiquidity(_paramsB);
        assertEq(_amount0, _amount0_ + 1);
        assertEq(_amount1, _amount1_ + 1);

        uint128 _liquidity2 = liquidityPool.getCurrentLiquidity(lowerTick, upperTick);
        console2.log(_liquidity2, "liquidity2");
        assertEq(_liquidity, _liquidity2);
        _consoleBalance();

        //swap
        multiSwapByCarol();

        //compute current fee and position
        IOrangeLiquidityPool.Params memory _params = IOrangeLiquidityPool.Params(
            address(token0),
            address(token1),
            lowerTick,
            upperTick
        );
        (uint256 fee0, uint256 fee1) = liquidityPool.getFeesEarned(_params);
        console2.log(fee0, fee1);
        (_amount0, _amount1) = liquidityPool.getAmountsForLiquidity(_paramsB);
        uint _balance0 = token0.balanceOf(address(this));
        uint _balance1 = token1.balanceOf(address(this));

        // burn and collect
        IOrangeLiquidityPool.ParamsOfLiquidity memory _paramsBurn = IOrangeLiquidityPool.ParamsOfLiquidity(
            address(token0),
            address(token1),
            lowerTick,
            upperTick,
            _liquidity
        );
        (uint burn0_, uint burn1_) = liquidityPool.burn(_paramsBurn);
        assertEq(_amount0, burn0_);
        assertEq(_amount1, burn1_);
        _consoleBalance();

        (uint collect0, uint collect1) = liquidityPool.collect(_params);
        console2.log(collect0, collect1);
        assertEq(_balance0 + fee0 + burn0_, token0.balanceOf(address(this)));
        assertEq(_balance1 + fee1 + burn1_, token1.balanceOf(address(this)));
        _consoleBalance();
    }

    // function test_delegateMint_Success() public {
    //     //mint
    //     IOrangeLiquidityPool.ParamsOfAmount memory _paramsA = IOrangeLiquidityPool.ParamsOfAmount(
    //         address(token0),
    //         address(token1),
    //         lowerTick,
    //         upperTick,
    //         1 ether,
    //         1000 * 1e6
    //     );
    //     uint128 _liquidity = liquidityPool.getLiquidityForAmounts(_paramsA);

    //     IOrangeLiquidityPool.MintParams memory _mintParams = IOrangeLiquidityPool.MintParams(
    //         address(token0),
    //         address(token1),
    //         address(this),
    //         lowerTick,
    //         upperTick,
    //         _liquidity
    //     );

    //     bool success;
    //     bytes memory data;
    //     (success, data) = address(liquidityPool).delegatecall(
    //         abi.encodeWithSelector(IOrangeLiquidityPool.mint.selector, _mintParams)
    //     );
    //     (uint _amount0, uint _amount1) = abi.decode(data, (uint, uint));
    //     console2.log(_amount0, _amount1);

    //     IOrangeLiquidityPool.ParamsOfLiquidity memory _paramsB = IOrangeLiquidityPool.ParamsOfLiquidity(
    //         address(token0),
    //         address(token1),
    //         lowerTick,
    //         upperTick,
    //         _liquidity
    //     );

    //     (uint _amount0_, uint _amount1_) = liquidityPool.getAmountsForLiquidity(_paramsB);
    //     assertEq(_amount0, _amount0_ + 1);
    //     assertEq(_amount1, _amount1_ + 1);

    //     uint128 _liquidity2 = liquidityPool.getLiquidity(lowerTick, upperTick);
    //     console2.log(_liquidity2, "liquidity2");
    //     assertEq(_liquidity, _liquidity2);

    //     //swap
    //     multiSwapByCarol();

    //     //burn half
    //     IOrangeLiquidityPool.ParamsOfLiquidity memory _paramsBurn = IOrangeLiquidityPool.ParamsOfLiquidity(
    //         address(token0),
    //         address(token1),
    //         lowerTick,
    //         upperTick,
    //         _liquidity / 2
    //     );
    //     //old
    //     // (uint burn0_, uint burn1_) = pool.burn(_paramsBurn.lowerTick, _paramsBurn.upperTick, _paramsBurn.liquidity);

    //     (success, data) = address(liquidityPool).delegatecall(
    //         abi.encodeWithSelector(IOrangeLiquidityPool.burn.selector, _paramsBurn)
    //     );
    //     (uint burn0_, uint burn1_) = abi.decode(data, (uint, uint));

    //     console2.log(burn0_, burn1_);
    //     assertApproxEqAbs(burn0_, _amount0 / 2, 1);
    //     assertApproxEqAbs(burn1_, _amount1 / 2, 1);

    //     //collect fees
    // }
}
