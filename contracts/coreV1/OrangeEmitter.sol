// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeVaultV1} from "../interfaces/IOrangeVaultV1.sol";
import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";

contract OrangeEmitter {
    mapping(address => bool) public strategists;
    address[] public alphaVaults;
    address[] public vaultV1s;

    /* ========== MODIFIER ========== */
    modifier onlyStrategist() {
        require(strategists[msg.sender], "ONLY_STRATEGIST");
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor() {
        _setStrategist(msg.sender, true);
    }

    /* ========== WRITE FUNCTIONS ========== */
    function setStrategist(address _strategist, bool _status) external onlyStrategist {
        _setStrategist(_strategist, _status);
    }

    function _setStrategist(address _strategist, bool _status) internal {
        strategists[_strategist] = _status;
    }

    function pushAlphaVault(address _alphaVault) external onlyStrategist {
        alphaVaults.push(_alphaVault);
    }

    function pushVaultV1(address _vaultV1) external onlyStrategist {
        vaultV1s.push(_vaultV1);
    }

    function removeAlphaVault(address _alphaVault) external onlyStrategist {
        uint8 length = uint8(alphaVaults.length);
        for (uint8 i = 0; i < length; i++) {
            if (alphaVaults[i] == _alphaVault) {
                alphaVaults[i] = alphaVaults[length - 1];
                alphaVaults.pop();
                break;
            }
        }
    }

    function removeVaultV1(address _vaultV1) external onlyStrategist {
        uint8 length = uint8(vaultV1s.length);
        for (uint8 i = 0; i < length; i++) {
            if (vaultV1s[i] == _vaultV1) {
                vaultV1s[i] = vaultV1s[length - 1];
                vaultV1s.pop();
                break;
            }
        }
    }

    function emitActionAlpha() external onlyStrategist {
        uint8 length = uint8(alphaVaults.length);
        for (uint8 i = 0; i < length; i++) {
            IOrangeAlphaVault(alphaVaults[i]).emitAction();
        }
    }

    function emitActionV1() external onlyStrategist {
        uint8 length = uint8(vaultV1s.length);
        for (uint8 i = 0; i < length; i++) {
            IOrangeVaultV1(vaultV1s[i]).emitAction(IOrangeVaultV1.ActionType.MANUAL);
        }
    }
}
