// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

abstract contract Initializable {
    uint8 private initialized; // 0: not initialized, 1: initialized
    event Initialized();

    modifier initializer() {
        require(initialized == 0, "Initializer: already initialized");
        initialized = 1;
        _;
        emit Initialized();
    }
}
