// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

import "../../../contracts/vendor/uniswap/FullMath.sol";

contract FullMathTest is BaseTest {
    using Ints for int24;

    function setUp() public {}

    function testMulDiv() public {
        uint256 ret = FullMath.mulDiv(3, 20, 40);
        console2.log(ret);
        uint256 ret2 = FullMath.mulDivRoundingUp(3, 20, 40);
        console2.log(ret2);
    }
}
