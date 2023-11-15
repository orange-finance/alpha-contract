// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {FixedPoint128} from "@uniswap/v3-core/contracts/libraries/FixedPoint128.sol";

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";

import {ILiquidityPoolManager} from "@src/interfaces/ILiquidityPoolManager.sol";
import {TickMath} from "@src/libs/uniswap/TickMath.sol";
import {FullMath, LiquidityAmounts} from "@src/libs/uniswap/LiquidityAmounts.sol";
import {ILiquidityPoolCollectable, PerformanceFee} from "@src/poolManager/libs/PerformanceFee.sol";
import {IOrangeVaultV1} from "@src/interfaces/IOrangeVaultV1.sol";

import {IDopexV2PositionManager} from "@src/vendor/dopexV2/IDopexV2PositionManager.sol";
import {IUniswapV3SingleTickLiquidityHandler} from "@src/vendor/dopexV2/IUniswapV3SingleTickLiquidityHandler.sol";

interface IMulticallProvider {
    function multicall(bytes[] calldata data) external returns (bytes[] memory results);
}

contract DopexV2LiquidityPoolManager is Ownable, ILiquidityPoolManager {
    using SafeERC20 for IERC20;
    using TickMath for int24;
    using PerformanceFee for ILiquidityPoolCollectable;

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
        address _vault = vault;
        IUniswapV3SingleTickLiquidityHandler _handler = handler;
        int24 _ticks = (upperTick - lowerTick) / tickSpacing;

        int24 _t = lowerTick;
        uint128 _l = liquidity / uint128(uint24(_ticks));
        uint256 _pos = 0;

        // create call data for multicall
        bytes[] memory _mcd = new bytes[](uint256(uint24(_ticks)));
        bytes memory _md;
        uint256[] memory _amounts;

        for (int24 _nt = _t + tickSpacing; _nt < upperTick; ) {
            _md = abi.encode(pool, _t, _nt, _l);
            _mcd[_pos] = abi.encodeWithSelector(positionManager.mintPosition.selector, _handler, _md);

            (, _amounts) = _handler.tokensToPullForMint(_md);
            a0 += _amounts[0];
            a1 += _amounts[1];

            unchecked {
                _t = _nt;
                _nt += tickSpacing;
                _pos++;
            }
        }

        if (_pos != uint256(uint24(_ticks))) revert("INVALID_TICKS");

        // including remaining liquidity to the last tick
        uint128 _rem = liquidity % uint128(uint24(_ticks));
        _md = abi.encode(pool, _t, upperTick, _l + _rem);
        _mcd[_pos] = abi.encodeWithSelector(positionManager.mintPosition.selector, _handler, _md);

        // receive tokens from a vault
        address[] memory _tokens;
        (_tokens, _amounts) = _handler.tokensToPullForMint(_md);
        a0 += _amounts[0];
        a1 += _amounts[1];

        IERC20(_tokens[0]).safeTransferFrom(_vault, address(this), a0);
        IERC20(_tokens[1]).safeTransferFrom(_vault, address(this), a1);

        IMulticallProvider(address(positionManager)).multicall(_mcd);

        return reversed ? (a1, a0) : (a0, a1);
    }

    function burnAndCollect(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external onlyVault returns (uint256 got0, uint256 got1) {
        if (liquidity == 0) return (0, 0);

        address _vault = vault;
        IUniswapV3SingleTickLiquidityHandler _handler = handler;

        // calculate performance fee before burning position
        (uint256 _pf0, uint256 _pf1) = _performanceFee(lowerTick, upperTick);

        // cache before balance
        (address _t0, address _t1) = (pool.token0(), pool.token1());
        uint256 _pre0 = IERC20(_t0).balanceOf(address(this));
        uint256 _pre1 = IERC20(_t1).balanceOf(address(this));

        // burn position
        // uint256 _shares = IUniswapV3SingleTickLiquidityHandler(address(handler)).convertToShares(liquidity);
        // bytes memory _burnPositionData = abi.encode(pool, lowerTick, upperTick, _shares);
        // positionManager.burnPosition(_handler, _burnPositionData);

        int24 _ticks = (upperTick - lowerTick) / tickSpacing;
        uint24 _ticksU24 = uint24(_ticks);

        // TODO: implement multicall
        bytes[] memory _mcData = new bytes[](uint256(_ticksU24));

        IMulticallProvider(address(positionManager)).multicall(_mcData);

        // tokens to receive
        got0 = IERC20(_t0).balanceOf(address(this)) - (_pre0 + _pf0);
        got1 = IERC20(_t1).balanceOf(address(this)) - (_pre1 + _pf1);

        // send tokens to a vault
        IERC20(_t0).safeTransfer(_vault, got0);
        IERC20(_t1).safeTransfer(_vault, got1);

        if (reversed) (got0, got1) = (got1, got0);
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

    function getCurrentTick() external view returns (int24 tick) {
        (, tick, , , , , ) = pool.slot0();
    }

    // TODO: fix
    function getCurrentLiquidity(int24 _lowerTick, int24 _upperTick) external view returns (uint128 liquidity) {
        IUniswapV3SingleTickLiquidityHandler _handler = handler;
        uint256 _tid = _handler.getHandlerIdentifier(abi.encode(pool, _lowerTick, _upperTick));
        uint256 _share = IERC1155(address(handler)).balanceOf(address(this), _tid);

        liquidity = _handler.convertToAssets(_share);
    }

    // TODO: fix
    function getAmountsForLiquidity(
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity
    ) external view returns (uint256, uint256) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            lowerTick.getSqrtRatioAtTick(),
            upperTick.getSqrtRatioAtTick(),
            liquidity
        );
        return reversed ? (amount1, amount0) : (amount0, amount1);
    }

    // TODO: fix
    function getLiquidityForAmounts(
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1
    ) external view returns (uint128 liquidity) {
        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();
        (uint256 _amount0, uint256 _amount1) = reversed ? (amount1, amount0) : (amount0, amount1);

        return
            LiquidityAmounts.getLiquidityForAmounts(
                _sqrtRatioX96,
                lowerTick.getSqrtRatioAtTick(),
                upperTick.getSqrtRatioAtTick(),
                _amount0,
                _amount1
            );
    }

    function validateTicks(int24 _lowerTick, int24 _upperTick) external view {
        int24 _spacing = pool.tickSpacing();
        if (_lowerTick < _upperTick && _lowerTick % _spacing == 0 && _upperTick % _spacing == 0) {
            return;
        }
        revert("INVALID_TICKS");
    }

    // TODO: fix
    function getFeesEarned(int24 lowerTick, int24 upperTick) public view returns (uint256 fee0, uint256 fee1) {
        IUniswapV3SingleTickLiquidityHandler _handler = handler;
        uint256 _tid = _handler.getHandlerIdentifier(abi.encode(pool, lowerTick, upperTick));
        IUniswapV3SingleTickLiquidityHandler.TokenIdInfo memory _ti = _handler.tokenIds(_tid);

        (uint128 _tokensOwed0, uint128 _tokensOwed1) = _getAllFeeOwed(lowerTick, upperTick);

        (uint160 _sqrtRatioX96, , , , , , ) = pool.slot0();

        uint128 _uLiqTotal = _handler.convertToAssets(IERC1155(address(_handler)).balanceOf(address(this), _tid));

        uint160 _sqrtRatioAX96 = lowerTick.getSqrtRatioAtTick();
        uint160 _sqrtRatioBX96 = upperTick.getSqrtRatioAtTick();

        (uint256 _uLiq0, uint256 _uLiq1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            _sqrtRatioAX96,
            _sqrtRatioBX96,
            _uLiqTotal
        );

        (uint256 _total0, uint256 _total1) = LiquidityAmounts.getAmountsForLiquidity(
            _sqrtRatioX96,
            _sqrtRatioAX96,
            _sqrtRatioBX96,
            _ti.totalLiquidity
        );

        if (reversed) {
            fee0 = (_tokensOwed1 * _uLiq1) / _total1;
            fee1 = (_tokensOwed0 * _uLiq0) / _total0;
        } else {
            fee0 = (_tokensOwed0 * _uLiq0) / _total0;
            fee1 = (_tokensOwed1 * _uLiq1) / _total1;
        }
    }

    // TODO: fix
    function _getAllFeeOwed(int24 lowerTick, int24 upperTick) internal view returns (uint128, uint128) {
        IUniswapV3SingleTickLiquidityHandler _handler = handler;

        uint256 _tid = _handler.getHandlerIdentifier(abi.encode(pool, lowerTick, upperTick));
        IUniswapV3SingleTickLiquidityHandler.TokenIdInfo memory _ti = _handler.tokenIds(_tid);

        uint128 _totalLiquidity = _ti.totalLiquidity;
        uint128 _liquidityUsed = _ti.liquidityUsed;

        (
            ,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 _tokensOwed0,
            uint128 _tokensOwed1
        ) = pool.positions(keccak256(abi.encode(address(_handler), lowerTick, upperTick)));

        unchecked {
            _tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - _ti.feeGrowthInside0LastX128,
                    // _ti.totalLiquidity - _ti.liquidityUsed,
                    _totalLiquidity - _liquidityUsed,
                    FixedPoint128.Q128
                )
            );
            _tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - _ti.feeGrowthInside1LastX128,
                    // _ti.totalLiquidity - _ti.liquidityUsed,
                    _totalLiquidity - _liquidityUsed,
                    FixedPoint128.Q128
                )
            );
        }

        return (_tokensOwed0, _tokensOwed1);
    }
}
