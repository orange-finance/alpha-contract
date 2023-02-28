// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {OrangeAlphaPeriphery} from "../core/OrangeAlphaPeriphery.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaPeripheryMock is OrangeAlphaPeriphery {
    int24 public twap;

    constructor(address _vault, address _params)
        OrangeAlphaPeriphery(_vault, _params)
    {}

    function setTwap(int24 _twap) external {
        twap = _twap;
    }

    function _isAllowlisted(address, bytes32[] calldata)
        internal
        view
        override
    {
        //merkle proof is tested in hardhat tests by typescripts
    }

    function getTwap() external view returns (int24) {
        return _getTwap();
    }

    function _getTwap() internal view override returns (int24) {
        return twap;
    }
}
