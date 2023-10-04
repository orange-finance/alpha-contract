// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.16;

abstract contract Mock {
    mapping(bytes4 => uint256) public uint256Returns;
    mapping(bytes4 => uint24) public uint24Returns;
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

    function setUint256ReturnValue(bytes4 _sig, uint256 _val) public {
        uint256Returns[_sig] = _val;
    }

    function setUint24ReturnValue(bytes4 _sig, uint24 _val) public {
        uint24Returns[_sig] = _val;
    }

    function setAddressReturnValue(bytes4 _sig, address _val) public {
        addressReturns[_sig] = _val;
    }

    function setBoolReturnValue(bytes4 _sig, bool _val) public {
        boolReturns[_sig] = _val;
    }

    function setBytes32ReturnValue(bytes4 _sig, bytes32 _val) public {
        bytes32Returns[_sig] = _val;
    }

    function setBytesReturnValue(bytes4 _sig, bytes memory _val) public {
        bytesReturns[_sig] = _val;
    }

    function setStringReturnValue(bytes4 _sig, string memory _val) public {
        stringReturns[_sig] = _val;
    }

    function setRevert(bytes4 _sig) public {
        shouldRevert[_sig] = true;
    }
}
