// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

contract Mock {
    mapping(bytes4 => uint256) public uint256Returns;
    mapping(bytes4 => address) public addressReturns;
    mapping(bytes4 => bool) public boolReturns;
    mapping(bytes4 => bytes32) public bytes32Returns;
    mapping(bytes4 => bytes) public bytesReturns;
    mapping(bytes4 => string) public stringReturns;

    mapping(bytes4 => bool) public shouldRevert;

    modifier mayRevert(bytes4 _sig) {
        if (shouldRevert[_sig]) {
            revert("Mock reverted");
        }
        _;
    }

    function setReturnValue(bytes4 _sig, uint256 _val) public {
        uint256Returns[_sig] = _val;
    }

    function setReturnValue(bytes4 _sig, address _val) public {
        addressReturns[_sig] = _val;
    }

    function setReturnValue(bytes4 _sig, bool _val) public {
        boolReturns[_sig] = _val;
    }

    function setReturnValue(bytes4 _sig, bytes32 _val) public {
        bytes32Returns[_sig] = _val;
    }

    function setReturnValue(bytes4 _sig, bytes memory _val) public {
        bytesReturns[_sig] = _val;
    }

    function setReturnValue(bytes4 _sig, string memory _val) public {
        stringReturns[_sig] = _val;
    }

    function setRevert(bytes4 _sig) public {
        shouldRevert[_sig] = true;
    }
}
