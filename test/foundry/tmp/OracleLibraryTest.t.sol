// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../../contracts/libs/uniswap/LiquidityAmounts.sol";
import "../../../contracts/libs/uniswap/OracleLibrary.sol";
import "../../../contracts/libs/uniswap/TickMath.sol";

contract OracleLibraryTest is BaseTest {
    using stdStorage for StdStorage;
    using OracleLibrary for IUniswapV3Pool;

    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;

    IUniswapV3Pool pool;
    IERC20 weth;
    IERC20 usdc;

    function setUp() public {
        (tokenAddr, , uniswapAddr) = AddressHelper.addresses(block.chainid);

        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        weth = IERC20(tokenAddr.wethAddr);
        usdc = IERC20(tokenAddr.usdcAddr);
    }

    function testObserve() public {
        uint32[] memory secondsAgos = new uint32[](1);
        // console2.log(block.timestamp);
        secondsAgos[0] = uint32(0);
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(
            secondsAgos
        );
        console2.log(uint56(tickCumulatives[0]), secondsPerLiquidityCumulativeX128s[0]);
    }

    function testTick() public {
        (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = pool.consult(1);
        console2.log(uint24(arithmeticMeanTick), harmonicMeanLiquidity);

        address[] memory tokens = new address[](2);
        int24[] memory ticks = new int24[](1);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);
        ticks[0] = arithmeticMeanTick;

        int256 syntheticTick = OracleLibrary.getChainedPrice(tokens, ticks);
        console2.log(uint256(syntheticTick));
    }
}
