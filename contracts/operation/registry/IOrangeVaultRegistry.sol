// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IOrangeVaultRegistry {
    event VaultAdded(address indexed vault, string indexed version, address indexed parameters);
    event VaultRemoved(address indexed vault);

    struct VaultDetail {
        string version;
        address parameters;
    }

    function numVaults() external view returns (uint256);

    function getDetailOf(address _vault) external view returns (VaultDetail memory);

    function add(address _vault, string calldata _version, address _parameters) external;

    function remove(address _vault) external;
}
