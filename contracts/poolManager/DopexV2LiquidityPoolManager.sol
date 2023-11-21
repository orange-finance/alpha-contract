// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {ILiquidityPoolManager} from "@src/interfaces/ILiquidityPoolManager.sol";
import {TickMath} from "@src/libs/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "@src/libs/uniswap/LiquidityAmounts.sol";
import {ILiquidityPoolCollectable, PerformanceFee} from "@src/poolManager/libs/PerformanceFee.sol";
import {IOrangeVaultV1} from "@src/interfaces/IOrangeVaultV1.sol";

import {IDopexV2PositionManager} from "@src/vendor/dopexV2/IDopexV2PositionManager.sol";
import {IUniswapV3SingleTickLiquidityHandler} from "@src/vendor/dopexV2/IUniswapV3SingleTickLiquidityHandler.sol";

import {DopexUniV3HandlerLib} from "@src/poolManager/libs/DopexUniV3HandlerLib.sol";

import "forge-std/console2.sol";

interface IMulticallProvider {
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}

contract DopexV2LiquidityPoolManager is Ownable, ERC1155Holder, ILiquidityPoolManager {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using FullMath for uint256;
    using PerformanceFee for ILiquidityPoolCollectable;
    using DopexUniV3HandlerLib for IUniswapV3SingleTickLiquidityHandler;

    uint16 private constant MAGIC_SCALE_1E4 = 10000; //for slippage

    IUniswapV3Pool public immutable pool;
    int24 public immutable tickSpacing;
    IDopexV2PositionManager public immutable positionManager;
    IUniswapV3SingleTickLiquidityHandler public immutable handler;

    uint24 public immutable fee;
    bool public immutable reversed; //if baseToken > targetToken of Vault, true
    address public immutable vault;
    address perfFeeRecipient;
    uint128 public perfFeeDivisor = 10; // 10% of profit

    modifier onlyVault() {
        if (msg.sender != vault) revert("ONLY_VAULT");
        _;
    }

    constructor(address vault_, address pool_, address positionManager_, address handler_) {
        vault = vault_;
        pool = IUniswapV3Pool(pool_);
        positionManager = IDopexV2PositionManager(positionManager_);
        handler = IUniswapV3SingleTickLiquidityHandler(handler_);

        reversed = IOrangeVaultV1(vault_).token0() > IOrangeVaultV1(vault_).token1();
        fee = pool.fee();
        tickSpacing = pool.tickSpacing();

        IERC20(pool.token0()).safeApprove(positionManager_, type(uint256).max);
        IERC20(pool.token1()).safeApprove(positionManager_, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    Admin Action
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function setPerfFeeRecipient(address _perfFeeRecipient) external onlyOwner {
        perfFeeRecipient = _perfFeeRecipient;
    }

    /**
     * @dev set performance fee divisor
     * @param _perfFeeDivisor divisor of performance fee. setting 0 will disable performance fee
     */
    function setPerfFeeDivisor(uint128 _perfFeeDivisor) external onlyOwner {
        perfFeeDivisor = _perfFeeDivisor;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    Position Management
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function mint(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external onlyVault returns (uint256 a0, uint256 a1) {
        // address _vault = vault;
        // IUniswapV3SingleTickLiquidityHandler _handler = handler;

        // create call data for multicall (reserve max size)
        bytes[] memory _mcd = new bytes[](uint256(uint24((upperTick - lowerTick) / tickSpacing - 1)));
        bytes memory _md;
        int24 _t = lowerTick;
        uint256 _pos = 0;
        uint256[] memory _amounts;

        for (int24 _nt = _t + tickSpacing; _nt <= upperTick; ) {
            int24 _ct = getCurrentTick();

            unchecked {
                // as Dopex not support in-range LP, only mint if the tick is not crossed
                if (_shouldMint(_t, _nt) && _nt - _ct > tickSpacing) {
                    _md = abi.encode(pool, _t, _nt, liquidity);
                    _mcd[_pos] = abi.encodeWithSelector(positionManager.mintPosition.selector, handler, _md);

                    (, _amounts) = handler.tokensToPullForMint(abi.encode(pool, _t, _nt, liquidity));
                    a0 += _amounts[0];
                    a1 += _amounts[1];
                    _pos++;
                }

                _t = _nt;
                _nt += tickSpacing;
            }
        }

        // create final call data (remove empty bytes)
        bytes[] memory _final = new bytes[](uint256(uint24(_pos)));

        for (uint256 i = 0; i < _pos; i++) {
            _final[i] = _mcd[i];
        }

        // pull tokens from a vault
        IERC20(pool.token0()).safeTransferFrom(vault, address(this), a0);
        IERC20(pool.token1()).safeTransferFrom(vault, address(this), a1);

        console2.log("before 0: %d", IERC20(pool.token0()).balanceOf(address(this)));
        console2.log("before 1: %d", IERC20(pool.token1()).balanceOf(address(this)));

        // check if multicall is valid
        IMulticallProvider(address(positionManager)).multicall(_final);

        console2.log("after 0: %d", IERC20(pool.token0()).balanceOf(address(this)));
        console2.log("after 1: %d", IERC20(pool.token1()).balanceOf(address(this)));

        uint256 _refund0 = IERC20(pool.token0()).balanceOf(address(this));
        uint256 _refund1 = IERC20(pool.token1()).balanceOf(address(this));

        if (_refund0 > 0) {
            IERC20(pool.token0()).safeTransfer(vault, _refund0);
            a0 -= _refund0;
        }

        if (_refund1 > 0) {
            IERC20(pool.token1()).safeTransfer(vault, _refund1);
            a1 -= _refund1;
        }

        return reversed ? (a1, a0) : (a0, a1);
    }

    function burnAndCollect(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external onlyVault returns (uint256 got0, uint256 got1) {
        if (liquidity == 0) return (0, 0);
        // // cache assets to be subtracted from the final balance
        (address _t0, address _t1) = (pool.token0(), pool.token1());
        uint256 _pre0 = IERC20(_t0).balanceOf(address(this));
        uint256 _pre1 = IERC20(_t1).balanceOf(address(this));

        // wrap logic to avoid stack too deep error
        (bytes[] memory _mcd, uint256 _pf0, uint256 _pf1) = _prepareBatchBurn(lowerTick, upperTick, liquidity);

        IMulticallProvider(address(positionManager)).multicall(_mcd);

        // calculate tokens to be sent to a vault
        got0 = IERC20(_t0).balanceOf(address(this)) - (_pre0 + _pf0);
        got1 = IERC20(_t1).balanceOf(address(this)) - (_pre1 + _pf1);

        // send tokens to a vault
        IERC20(_t0).safeTransfer(address(vault), got0);
        IERC20(_t1).safeTransfer(address(vault), got1);

        if (reversed) (got0, got1) = (got1, got0);
    }

    function _prepareBatchBurn(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) internal view returns (bytes[] memory burnMulticallData, uint256 perfFee0, uint256 perfFee1) {
        IUniswapV3SingleTickLiquidityHandler _handler = handler;

        uint128 _total = _handler.getLiquidityAverageInRange(pool, lowerTick, upperTick, tickSpacing);

        // create call data for multicall
        burnMulticallData = new bytes[](uint256(uint24((upperTick - lowerTick) / tickSpacing)));
        int24 _t = lowerTick;
        uint256 _pos = 0;
        for (int24 _nt = _t + tickSpacing; _nt < upperTick; ) {
            uint256 _shares = _handler.getTotalSingleTickShares(pool, _t, tickSpacing);

            burnMulticallData[_pos] = abi.encodeWithSelector(
                positionManager.burnPosition.selector,
                _handler,
                abi.encode(pool, _t, _nt, _shares.mulDiv(liquidity, _total))
            );

            // calculate performance fee
            (uint256 _pf0, uint256 _pf1) = _performanceFee(_t, _nt);

            unchecked {
                // add to the amount to be subtracted
                perfFee0 += _pf0;
                perfFee1 += _pf1;

                // update tick
                _t = _nt;
                _nt += tickSpacing;
                _pos++;
            }
        }
    }

    function _performanceFee(int24 lowerTick, int24 upperTick) internal view returns (uint256 fee0, uint256 fee1) {
        if (perfFeeRecipient == address(0) || perfFeeDivisor == 0) return (0, 0);

        (uint256 _f0, uint256 _f1) = getFeesEarned(lowerTick, upperTick);
        fee0 = _f0 / perfFeeDivisor;
        fee1 = _f1 / perfFeeDivisor;
        // sort in uniV3's manner
        if (reversed) (fee0, fee1) = (fee1, fee0);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    Pool State
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function getTwap(uint32 _minute) external view returns (int24 avgTick) {
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _minute;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgo);

        if (tickCumulatives.length != 2) revert("array len");
        unchecked {
            avgTick = int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(_minute)));
        }
    }

    function getCurrentTick() public view returns (int24 tick) {
        (, tick, , , , , ) = pool.slot0();
    }

    /// @notice take average of the all single ticks in the range, because the liquidity is not evenly distributed (dynamic against share)
    function getCurrentLiquidity(int24 lowerTick, int24 upperTick) external view returns (uint128 liquidity) {
        return handler.getLiquidityAverageInRange(pool, lowerTick, upperTick, tickSpacing);
    }

    /// @notice get amount of tokens to provide liquidity(average) in the range
    function getAmountsForLiquidity(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external view returns (uint256 amount0, uint256 amount1) {
        int24 _ct = getCurrentTick();
        int24 _t = lowerTick;
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        for (int24 _nt = _t + tickSpacing; _nt <= upperTick; ) {
            if (_shouldMint(_t, _nt) && _nt - _ct > tickSpacing) {
                (uint256 _amount0, uint256 _amount1) = LiquidityAmounts.getAmountsForLiquidity(
                    _sqrtRatioX96,
                    TickMath.getSqrtRatioAtTick(_t),
                    TickMath.getSqrtRatioAtTick(_nt),
                    liquidity
                );

                amount0 += _amount0;
                amount1 += _amount1;
            }

            unchecked {
                _t = _nt;
                _nt += tickSpacing;
            }
        }

        if (reversed) (amount1, amount0) = (amount0, amount1);
    }

    /// @notice get liquidity(average) for given token amounts in the range
    function getLiquidityForAmounts(
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) external view returns (uint128 liquidity) {
        // (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        // (uint256 _amount0, uint256 _amount1) = reversed ? (amount1, amount0) : (amount0, amount1);

        // return
        //     LiquidityAmounts.getLiquidityForAmounts(
        //         _sqrtRatioX96,
        //         lowerTick.getSqrtRatioAtTick(),
        //         upperTick.getSqrtRatioAtTick(),
        //         _amount0,
        //         _amount1
        //     );

        int24 _ct = getCurrentTick();
        int24 _t = lowerTick;
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        for (int24 _nt = _t + tickSpacing; _nt <= upperTick; ) {
            if (_shouldMint(_t, _nt) && _nt - _ct > tickSpacing) {
                liquidity += LiquidityAmounts.getLiquidityForAmounts(
                    _sqrtRatioX96,
                    TickMath.getSqrtRatioAtTick(_t),
                    TickMath.getSqrtRatioAtTick(_nt),
                    amount0,
                    amount1
                );
            }

            unchecked {
                _t = _nt;
                _nt += tickSpacing;
            }
        }
    }

    function validateTicks(int24 _lowerTick, int24 _upperTick) external view {
        int24 _spacing = tickSpacing;
        if (_lowerTick < _upperTick && _lowerTick % _spacing == 0 && _upperTick % _spacing == 0) {
            return;
        }
        revert("INVALID_TICKS");
    }

    function getFeesEarned(int24 lowerTick, int24 upperTick) public view returns (uint256 fee0, uint256 fee1) {
        (fee0, fee1) = handler.getFeesEarned(pool, lowerTick, upperTick);

        if (reversed) (fee0, fee1) = (fee1, fee0);
    }

    function _shouldMint(int24 lowerTick, int24 upperTick) internal view returns (bool) {
        (, , , uint128 _owed0, uint128 _owed1) = pool.positions(
            keccak256(abi.encodePacked(address(handler), lowerTick, upperTick))
        );

        if (_owed0 > 0 && _owed0 < 10) return false;

        if (_owed1 > 0 && _owed1 < 10) return false;

        return true;
    }
}
