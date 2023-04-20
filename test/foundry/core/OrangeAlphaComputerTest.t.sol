// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";
import {OrangeAlphaComputer, OrangeAlphaVault, IUniswapV3Pool} from "../../../contracts/core/OrangeAlphaComputer.sol";
import {OrangeAlphaParameters} from "../../../contracts/core/OrangeAlphaParameters.sol";
import {OrangeAlphaVault, IAaveV3Pool, IERC20} from "../../../contracts/core/OrangeAlphaVault.sol";

contract OrangeAlphaComputerTest is BaseTest {
    AddressHelper.TokenAddr public tokenAddr;
    AddressHelper.UniswapAddr uniswapAddr;
    AddressHelper.AaveAddr public aaveAddr;

    OrangeAlphaComputer computer;

    OrangeAlphaVault vault;
    IUniswapV3Pool public pool;
    IERC20 public token0;
    IERC20 public token1;
    OrangeAlphaParameters public params;

    function setUp() public {
        (tokenAddr, aaveAddr, uniswapAddr) = AddressHelper.addresses(block.chainid);

        params = new OrangeAlphaParameters();
        pool = IUniswapV3Pool(uniswapAddr.wethUsdcPoolAddr);
        token0 = IERC20(tokenAddr.wethAddr);
        token1 = IERC20(tokenAddr.usdcAddr);

        vault = new OrangeAlphaVault(
            "OrangeAlphaVault",
            "ORANGE_ALPHA_VAULT",
            address(pool),
            address(token0),
            address(token1),
            address(uniswapAddr.routerAddr),
            address(aaveAddr.poolAddr),
            address(aaveAddr.vDebtWethAddr),
            address(aaveAddr.ausdcAddr),
            address(params)
        );

        // vault = OrangeAlphaVault(0xhoge);
        // params = OrangeAlphaParameters(address(vault.params()));
        computer = new OrangeAlphaComputer(address(vault), address(params));
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function test_computeHedgeRatio() public {
        int24 _lowerTick = -200920;
        int24 _upperTick = -199740;
        uint256 _targetHdegeRatio = 195420000;

        uint _hedgeRatio = computer.computeApplyHedgeRatio(_lowerTick, _upperTick, _targetHdegeRatio);
        console2.log("hedgeRatio", _hedgeRatio);
    }
}
