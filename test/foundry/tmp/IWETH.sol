pragma solidity ^0.8.16;

interface IWETH {
    function deposit() external payable;
    function balanceOf(address hoge) external view returns(uint);
    function approve(address guy, uint wad) external returns (bool);
    function withdraw(uint wad) external;
    function transfer(address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external;
    function totalSupply() external view returns (uint);
}