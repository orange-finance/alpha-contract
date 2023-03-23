// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IAaveV3Pool} from "../interfaces/IAaveV3Pool.sol";
import {IVariableDebtToken} from "../interfaces/IVariableDebtToken.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {WadRayMath} from "./WadRayMath.sol";

// import "forge-std/console2.sol";

/**
 * @title Aave ERC20 AToken
 * @author Aave
 * @notice Implementation of the interest bearing token for the Aave protocol
 */
contract DebtTokenMock is IVariableDebtToken, ERC20 {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct UserState {
        uint256 balance;
        uint256 lastNormalizedVariableDebtsRate;
    }

    IAaveV3Pool public POOL;
    uint8 private immutable _decimal;
    address internal _underlyingAsset;
    UserState private _totalSupply;
    mapping(address => UserState) private _userState;

    /**
     * @dev Only pool can call functions marked by this modifier.
     **/
    modifier onlyPool() {
        require(msg.sender == address(POOL), "Errors.CALLER_MUST_BE_POOL");
        _;
    }

    /**
     * @dev Constructor.
     */
    constructor(
        address underlyingAsset,
        IAaveV3Pool pool,
        uint8 decimal,
        string memory aTokenName,
        string memory aTokenSymbol
    ) ERC20(aTokenName, aTokenSymbol) {
        _underlyingAsset = underlyingAsset;
        POOL = pool;
        _decimal = decimal;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _updateBalance(from);
        _updateBalance(to);

        uint256 fromBalance = _userState[from].balance;
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _userState[from].balance = fromBalance - amount;
        }
        _userState[to].balance += amount;

        emit Transfer(from, to, amount);
    }

    function _updateBalance(address _user) internal {
        uint256 _newNormalizedVariableDebt = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);

        _userState[_user] = UserState(balanceOf(_user), _newNormalizedVariableDebt);
        _totalSupply = UserState(totalSupply(), _newNormalizedVariableDebt);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function decimals() public view virtual override returns (uint8) {
        return _decimal;
    }

    /// @inheritdoc IERC20
    function balanceOf(address user) public view virtual override(ERC20) returns (uint256) {
        uint256 _newNormalizedVariableDebt = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);

        UserState memory oldState = _userState[user];
        uint256 _income;
        if (oldState.lastNormalizedVariableDebtsRate == 0) {
            _income = 0;
        } else {
            _income =
                (oldState.balance * (_newNormalizedVariableDebt - oldState.lastNormalizedVariableDebtsRate)) /
                oldState.lastNormalizedVariableDebtsRate;
        }
        return oldState.balance + _income;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual override(ERC20) returns (uint256) {
        uint256 _newNormalizedVariableDebt = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);

        UserState memory oldTotalSupply = _totalSupply;
        uint256 _incomeTotalSupply;
        if (oldTotalSupply.lastNormalizedVariableDebtsRate == 0) {
            _incomeTotalSupply = 0;
        } else {
            _incomeTotalSupply =
                (oldTotalSupply.balance *
                    (_newNormalizedVariableDebt - oldTotalSupply.lastNormalizedVariableDebtsRate)) /
                oldTotalSupply.lastNormalizedVariableDebtsRate;
        }
        return oldTotalSupply.balance + _incomeTotalSupply;
    }

    /// @inheritdoc IVariableDebtToken
    function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
        return _underlyingAsset;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @inheritdoc IVariableDebtToken
    function mint(
        address,
        address onBehalfOf,
        uint256 amount,
        uint256
    ) external virtual override onlyPool returns (bool, uint256) {
        require(amount != 0, "mint zero amount");
        require(onBehalfOf != address(0), "ERC20: mint to the zero address");

        _updateBalance(onBehalfOf);

        _totalSupply.balance += amount;
        _userState[onBehalfOf].balance += amount;

        emit Transfer(address(0), onBehalfOf, amount);
        return (true, amount);
    }

    /// @inheritdoc IVariableDebtToken
    function burn(address from, uint256 amount, uint256) external virtual override onlyPool returns (uint256) {
        require(amount != 0, "mint zero amount");
        require(from != address(0), "ERC20: mint to the zero address");

        _updateBalance(from);

        _totalSupply.balance -= amount;
        _userState[from].balance -= amount;

        emit Transfer(from, address(0), amount);
        return amount;
    }
}
