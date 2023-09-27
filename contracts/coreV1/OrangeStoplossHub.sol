// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

//interafaces
import {IOrangeStrategyHelperV1} from "../interfaces/IOrangeStrategyHelperV1.sol";
import {IResolver} from "../interfaces/IResolver.sol";

contract OrangeStoplossHub {
    mapping(address => bool) public strategists;
    address[] public helperV1s;

    /* ========== MODIFIER ========== */
    modifier onlyStrategist() {
        require(strategists[msg.sender], "ONLY_STRATEGIST");
        _;
    }

    /* ========== CONSTRUCTOR ========== */
    constructor() {
        _setStrategist(msg.sender, true);
    }

    /* ========== SETUP FUNCTIONS ========== */
    function setStrategist(address _strategist, bool _status) external onlyStrategist {
        _setStrategist(_strategist, _status);
    }

    function _setStrategist(address _strategist, bool _status) internal {
        strategists[_strategist] = _status;
    }

    function pushHelperV1(address _vaultV1) external onlyStrategist {
        helperV1s.push(_vaultV1);
    }

    function removeHelperV1(address _vaultV1) external onlyStrategist {
        uint8 length = uint8(helperV1s.length);
        for (uint8 i = 0; i < length; i++) {
            if (helperV1s[i] == _vaultV1) {
                helperV1s[i] = helperV1s[length - 1];
                helperV1s.pop();
                break;
            }
        }
    }

    /* ========== FUNCTIONS ========== */

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        address[] memory _vaults = _getStoplossVaults();

        if (_vaults.length != 0) {
            canExec = true;

            execPayload = abi.encodeWithSelector(this.stoplossBatch.selector, _vaults);
        } else {
            execPayload = bytes("No Stoploss Vault");
        }
    }

    function stoplossBatch(address[] memory _vaults) external onlyStrategist {
        for (uint i; i < _vaults.length; ) {
            IOrangeStrategyHelperV1(_vaults[i]).stoploss();

            unchecked {
                ++i;
            }
        }
    }

    function _getStoplossVaults() internal view returns (address[] memory _vaults, int24[] memory _twaps) {
        for (uint i; i < _vaults.length; ) {
            (bool isStoploss, bytes memory encodedData) = IResolver(_vaults[i]).checker(); //selector = stoploss

            if (isStoploss) {
                bytes memory slicedData = new bytes(encodedData.length - 4);
                for (uint j = 0; j < slicedData.length; j++) {
                    slicedData[j] = encodedData[j + 4];
                }

                (address _vault, int24 _twap) = abi.decode(slicedData, (address, int24));

                _vaults[i] = _vault;
                _twaps[i] = _twap;
            }

            unchecked {
                ++i;
            }
        }
    }
}
