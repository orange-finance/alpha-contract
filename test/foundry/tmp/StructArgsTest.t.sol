// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../utils/BaseTest.sol";

contract StructArgsTest is BaseTest {
    StructMock structMock;

    function setUp() public {
        structMock = new StructMock();
    }

    function test() public view {
        structMock.exec();
    }
}

contract StructMock {
    struct S {
        uint256 a;
        uint256 b;
        uint256 c;
    }

    function exec() external view {
        S memory s = S(1, 2, 3);
        console2.log(s.a, s.b, s.c);
        structArgs(s);
        console2.log(s.a, s.b, s.c);

        uint256 d = 7;
        console2.log(d, "d");
        primitiveArgs(d);
        console2.log(d, "d");

        console2.log(s.a, s.b, s.c);
        structArgs2(s);
        console2.log(s.a, s.b, s.c);

        console2.log(s.a, s.b, s.c);
        structArgs3(s);
        console2.log(s.a, s.b, s.c);
    }

    function structArgs(S memory _s) internal pure {
        _s.a = 4;
        _s.b = 5;
        _s.c = 6;
    }

    function structArgs2(S memory _s) internal pure {
        _s = S(11, 12, 13);
    }

    function structArgs3(S memory _s) internal pure {
        _s = getS();
    }

    function getS() internal pure returns (S memory) {
        return S(14, 15, 16);
    }

    function getThree()
        internal
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (17, 18, 19);
    }

    function primitiveArgs(uint256 _d) internal pure {
        _d = 8;
    }
}
