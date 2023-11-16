// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {IUniswapV3SingleTickLiquidityHandler} from "@src/vendor/dopexV2/IUniswapV3SingleTickLiquidityHandler.sol";

library DopexUniV3HandlerLib {
    function positionId(
        IUniswapV3SingleTickLiquidityHandler,
        address _pool,
        int24 _tickLower,
        int24 _tickUpper
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_pool, _tickLower, _tickUpper)));
    }

    function getSingleTickLiquidity(
        IUniswapV3SingleTickLiquidityHandler handler,
        address _pool,
        int24 tick,
        int24 spacing
    ) internal view returns (uint128) {
        uint256 _share = handler.balanceOf(address(this), positionId(handler, _pool, tick, tick + spacing));

        return handler.convertToAssets(_share);
    }
}
