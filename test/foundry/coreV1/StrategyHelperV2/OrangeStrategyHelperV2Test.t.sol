// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "@test/foundry/coreV1/OrangeVaultV1Initializable/Fixture.t.sol";
import {ILiquidityPoolManager} from "@src/coreV1/strategyHelper/OrangeStrategyHelperV1.sol";
import {UniswapV3Twap, IUniswapV3Pool} from "@src/libs/UniswapV3Twap.sol";
import {FullMath} from "@src/libs/uniswap/LiquidityAmounts.sol";
import {TickMath} from "@src/libs/uniswap/TickMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ARB_FORK_BLOCK_DEFAULT} from "../../Config.sol";

import {OrangeStrategyHelperV2} from "@src/coreV1/strategyHelper/OrangeStrategyHelperV2.sol";

contract OrangeStrategyHelperV2Test is Fixture {
    using UniswapV3Twap for IUniswapV3Pool;
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using Ints for int24;
    using Ints for int256;

    OrangeStrategyHelperV2 public helperV2;
    OrangeStrategyHelperV2 public b_helperV2;

    function setUp() public override {
        vm.createSelectFork("arb", ARB_FORK_BLOCK_DEFAULT);
        super.setUp();

        helperV2 = new OrangeStrategyHelperV2(address(vault));
        b_helperV2 = new OrangeStrategyHelperV2(address(b_vault));
        b_params.setHelper(address(b_helperV2));
    }

    function test_constructor_Success() public {
        assertEq(address(helperV2.vault()), address(vault));
        assertEq(helperV2.token0(), address(token0));
        assertEq(helperV2.token1(), address(token1));
        assertEq(helperV2.liquidityPool(), address(vault.liquidityPool()));
        assertEq(address(helperV2.params()), address(params));
        assertEq(helperV2.strategists(address(this)), true);
    }

    /** computeRebalancePosition cases
     * 1. Reverse, Straight (vault token0/1 vs amm token0/1)
     * 2. in-range, upper-out-range, lower-out-range
     * 3. Hedge%: 0%, 100% (better to perform buffer)
     *
     * case1: Straight, in-range, 0%
     * case2: Straight, in-range, 100%
     * case3: Straight, upper-out-range, 0%
     * case4: Straight, upper-out-range, 100%
     * case5: Straight, lower-out-range, 0%
     * case6: Straight, lower-out-range, 100%
     * case7: Reverse, in-range, 0%
     * case8: Reverse, in-range, 100%
     * case9: Reverse, upper-out-range, 0%
     * case10: Reverse, upper-out-range, 100%
     * case11: Reverse, lower-out-range, 0%
     * case12: Reverse, lower-out-range, 100%
     */

    //Straight & upper-out => token0 = 0
    //Straight & lower-out => token1 = 0
    //Reverse & upper-out => token1 = 0
    //Reverse & lower-out => token0 = 0

    uint256 assets0 = 1e18;
    uint256 ltv = 80e6; //80%

    function test_computeRebalancePosition_case1() public {
        //straight
        UniswapV3LiquidityPoolManager lm = liquidityPool;
        //in-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 100;
        int24 lowerTick = currentTick - 100;

        //0% Hedge
        uint256 _hedgeRatio = 0;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(lm, uint128(actualPosition.token1Balance), address(token1), address(token0)) -
            _quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0)) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, 0); //0% hedge
        assertEq(actualPosition.collateralAmount0, 0); //0% hedge
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case2() public {
        //straight
        UniswapV3LiquidityPoolManager lm = liquidityPool;
        //inrange
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 100;
        int24 lowerTick = currentTick - 100;

        //100% Hedge
        uint256 _hedgeRatio = 1e8;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(lm, uint128(actualPosition.token1Balance), address(token1), address(token0)) -
            _quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0)) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, actualPosition.token1Balance); //100% hedge
        assertApproxEqRel(
            actualPosition.collateralAmount0,
            uint256(_quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0))).mulDiv(
                MAGIC_SCALE_1E8,
                ltv
            ),
            0.0001e18
        ); //debt / ltv = collateral
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case3() public {
        //straight
        UniswapV3LiquidityPoolManager lm = liquidityPool;
        //upper-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick - 100;
        int24 lowerTick = currentTick - 200;

        //0% Hedge
        uint256 _hedgeRatio = 0;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(lm, uint128(actualPosition.token1Balance), address(token1), address(token0)) -
            _quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0)) +
            actualPosition.collateralAmount0;

        assertEq(actualPosition.token0Balance, 0); //token0 = 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, 0); //0% hedge
        assertEq(actualPosition.collateralAmount0, 0); //0% hedge
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case4() public {
        //straight
        UniswapV3LiquidityPoolManager lm = liquidityPool;
        //upper-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick - 100;
        int24 lowerTick = currentTick - 200;

        //100% Hedge
        uint256 _hedgeRatio = 1e8;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(lm, uint128(actualPosition.token1Balance), address(token1), address(token0)) -
            _quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0)) +
            actualPosition.collateralAmount0;

        assertEq(actualPosition.token0Balance, 0); //token0 = 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, actualPosition.token1Balance); //100% hedge
        assertApproxEqRel(
            actualPosition.collateralAmount0,
            uint256(_quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0))).mulDiv(
                MAGIC_SCALE_1E8,
                ltv
            ),
            0.0001e18
        ); //debt / ltv = collateral
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case5() public {
        //straight
        UniswapV3LiquidityPoolManager lm = liquidityPool;
        //lower-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 200;
        int24 lowerTick = currentTick + 100;

        //0% Hedge
        uint256 _hedgeRatio = 0;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(lm, uint128(actualPosition.token1Balance), address(token1), address(token0)) -
            _quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0)) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertEq(actualPosition.token1Balance, 0); //token1 = 0
        assertEq(actualPosition.debtAmount1, 0); //0% hedge
        assertEq(actualPosition.collateralAmount0, 0); //0% hedge
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case6() public {
        //straight
        UniswapV3LiquidityPoolManager lm = liquidityPool;
        //lower-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 200;
        int24 lowerTick = currentTick + 100;

        //100% Hedge
        uint256 _hedgeRatio = 1e8;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(lm, uint128(actualPosition.token1Balance), address(token1), address(token0)) -
            _quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0)) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertEq(actualPosition.token1Balance, 0); //token1 = 0
        assertEq(actualPosition.debtAmount1, actualPosition.token1Balance); //100% hedge
        assertApproxEqRel(
            actualPosition.collateralAmount0,
            uint256(_quoteCurrent(lm, uint128(actualPosition.debtAmount1), address(token1), address(token0))).mulDiv(
                MAGIC_SCALE_1E8,
                ltv
            ),
            0.0001e18
        ); //debt / ltv = collateral
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case7() public {
        //reverse
        UniswapV3LiquidityPoolManager lm = b_liquidityPool;
        //in-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 100;
        int24 lowerTick = currentTick - 100;

        //0% Hedge
        uint256 _hedgeRatio = 0;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(
                lm,
                uint128(actualPosition.token1Balance),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) -
            _quoteCurrent(
                lm,
                uint128(actualPosition.debtAmount1),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, 0); //0% hedge
        assertEq(actualPosition.collateralAmount0, 0); //0% hedge
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case8() public {
        //reverse
        UniswapV3LiquidityPoolManager lm = b_liquidityPool;
        //in-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 100;
        int24 lowerTick = currentTick - 100;

        //100% Hedge
        uint256 _hedgeRatio = 1e8;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(
                lm,
                uint128(actualPosition.token1Balance),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) -
            _quoteCurrent(
                lm,
                uint128(actualPosition.debtAmount1),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, actualPosition.token1Balance); //100% hedge
        assertApproxEqRel(
            actualPosition.collateralAmount0,
            uint256(
                _quoteCurrent(
                    lm,
                    uint128(actualPosition.debtAmount1),
                    address(b_vault.token0()),
                    address(b_vault.token0())
                )
            ).mulDiv(MAGIC_SCALE_1E8, ltv),
            0.0001e18
        ); //debt / ltv = collateral
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case9() public {
        //reverse
        UniswapV3LiquidityPoolManager lm = b_liquidityPool;
        assertEq(lm.reversed(), true);
        //upper-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick - 100;
        int24 lowerTick = currentTick - 200;

        //0% Hedge
        uint256 _hedgeRatio = 0;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = b_helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(
                lm,
                uint128(actualPosition.token1Balance),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) -
            _quoteCurrent(
                lm,
                uint128(actualPosition.debtAmount1),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertEq(actualPosition.token1Balance, 0); //token1 = 0
        assertEq(actualPosition.debtAmount1, 0); //0% hedge
        assertEq(actualPosition.collateralAmount0, 0); //0% hedge
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case10() public {
        //reverse
        UniswapV3LiquidityPoolManager lm = b_liquidityPool;
        //upper-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick - 100;
        int24 lowerTick = currentTick - 200;

        //100% Hedge
        uint256 _hedgeRatio = 1e8;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = b_helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(
                lm,
                uint128(actualPosition.token1Balance),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) -
            _quoteCurrent(
                lm,
                uint128(actualPosition.debtAmount1),
                address(b_vault.token0()),
                address(b_vault.token0())
            ) +
            actualPosition.collateralAmount0;

        assertGt(actualPosition.token0Balance, 0); //not 0
        assertEq(actualPosition.token1Balance, 0); //token1 = 0
        assertEq(actualPosition.debtAmount1, 0); //100% hedge
        assertEq(actualPosition.collateralAmount0, 0); //debt / ltv = collateral
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case11() public {
        //reverse
        UniswapV3LiquidityPoolManager lm = b_liquidityPool;
        //lower-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 200;
        int24 lowerTick = currentTick + 100;

        //0% Hedge
        uint256 _hedgeRatio = 0;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = b_helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        emit log_named_uint("actualPosition.token1", actualPosition.token1Balance);
        emit log_named_uint(
            "actualPosition.token1InToken0",
            _quoteCurrent(
                lm,
                uint128(actualPosition.token1Balance),
                address(b_vault.token1()),
                address(b_vault.token0())
            )
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(
                lm,
                uint128(actualPosition.token1Balance),
                address(b_vault.token1()),
                address(b_vault.token0())
            ) -
            _quoteCurrent(
                lm,
                uint128(actualPosition.debtAmount1),
                address(b_vault.token1()),
                address(b_vault.token0())
            ) +
            actualPosition.collateralAmount0;

        assertEq(actualPosition.token0Balance, 0); //token0 = 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, 0); //0% hedge
        assertEq(actualPosition.collateralAmount0, 0); //0% hedge
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function test_computeRebalancePosition_case12() public {
        //reverse
        UniswapV3LiquidityPoolManager lm = b_liquidityPool;
        //lower-out-range
        (, int24 currentTick, , , , , ) = lm.pool().slot0();
        int24 upperTick = currentTick + 200;
        int24 lowerTick = currentTick + 100;

        //100% Hedge
        uint256 _hedgeRatio = 1e8;

        //actual
        IOrangeVaultV1.Positions memory actualPosition = b_helperV2.computeRebalancePosition(
            assets0,
            lowerTick,
            upperTick,
            ltv,
            _hedgeRatio
        );

        uint256 acutualAmount0 = actualPosition.token0Balance +
            _quoteCurrent(
                lm,
                uint128(actualPosition.token1Balance),
                address(b_vault.token1()),
                address(b_vault.token0())
            ) -
            _quoteCurrent(
                lm,
                uint128(actualPosition.debtAmount1),
                address(b_vault.token1()),
                address(b_vault.token0())
            ) +
            actualPosition.collateralAmount0;

        assertEq(actualPosition.token0Balance, 0); //vaultToken0 = 0
        assertGt(actualPosition.token1Balance, 0); //not 0
        assertEq(actualPosition.debtAmount1, actualPosition.token1Balance); //100% hedge
        assertApproxEqRel(
            actualPosition.collateralAmount0,
            uint256(
                _quoteCurrent(
                    lm,
                    uint128(actualPosition.debtAmount1),
                    address(b_vault.token1()),
                    address(b_vault.token0())
                )
            ).mulDiv(MAGIC_SCALE_1E8, ltv),
            0.0001e18
        ); //debt / ltv = collateral
        assertApproxEqRel(acutualAmount0, assets0, 0.0001e18); //0.01%
    }

    function _quoteAtTick(
        int24 _tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256) {
        return OracleLibrary.getQuoteAtTick(_tick, baseAmount, baseToken, quoteToken);
    }

    function _quoteCurrent(
        UniswapV3LiquidityPoolManager lm,
        uint128 baseAmount,
        address vaultTokenBase,
        address vaultTokenQuote
    ) internal view returns (uint256) {
        int24 _tick = lm.getCurrentTick();
        bool reversed = lm.reversed();
        return
            !reversed
                ? _quoteAtTick(_tick, baseAmount, vaultTokenBase, vaultTokenQuote)
                : _quoteAtTick(_tick, baseAmount, vaultTokenQuote, vaultTokenBase);
    }
}
