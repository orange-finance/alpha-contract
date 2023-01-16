// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IAaveV3Pool} from "../interfaces/IAaveV3Pool.sol";
import {IAToken} from "../interfaces/IAToken.sol";
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
contract ATokenMock is IAToken, ERC20 {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    struct UserState {
        uint256 balance;
        uint256 lastNormalizedIncomesRate;
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

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
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
        uint256 _newNormalizedIncome = POOL.getReserveNormalizedIncome(_underlyingAsset);

        // console2.log("_updateBalance1 start");
        _userState[_user] = UserState(balanceOf(_user), _newNormalizedIncome);
        // console2.log("_updateBalance1 end");

        // console2.log("_updateBalance2 start");
        _totalSupply = UserState(totalSupply(), _newNormalizedIncome);
        // console2.log("_updateBalance2 end");
    }

    /* ========== VIEW FUNCTIONS ========== */

    function decimals() public view virtual override returns (uint8) {
        return _decimal;
    }

    /// @inheritdoc IERC20
    function balanceOf(address user) public view virtual override(IERC20, ERC20) returns (uint256) {
        uint256 _newNormalizedIncome = POOL.getReserveNormalizedIncome(_underlyingAsset);

        UserState memory oldState = _userState[user];
        uint256 _income;
        if(oldState.lastNormalizedIncomesRate == 0){
            _income = 0;
        }else{
            _income = oldState.balance * (_newNormalizedIncome - oldState.lastNormalizedIncomesRate) / oldState.lastNormalizedIncomesRate;
        }
        return oldState.balance + _income;
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        uint256 _newNormalizedIncome = POOL.getReserveNormalizedIncome(_underlyingAsset);

        UserState memory oldTotalSupply = _totalSupply;
        uint256 _incomeTotalSupply;
        if(oldTotalSupply.lastNormalizedIncomesRate == 0){
            _incomeTotalSupply = 0;
        }else{
            _incomeTotalSupply = oldTotalSupply.balance * (_newNormalizedIncome - oldTotalSupply.lastNormalizedIncomesRate) / oldTotalSupply.lastNormalizedIncomesRate;
        }
        return oldTotalSupply.balance + _incomeTotalSupply;
    }

    /// @inheritdoc IAToken
    function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
        return _underlyingAsset;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @inheritdoc IAToken
    function mint(
        address,
        address onBehalfOf,
        uint256 amount,
        uint256
    ) external virtual override onlyPool returns (bool) {
        require(amount != 0, "mint zero amount");
        require(onBehalfOf != address(0), "ERC20: mint to the zero address");

        _updateBalance(onBehalfOf);

        _totalSupply.balance += amount;
        _userState[onBehalfOf].balance += amount;

        emit Transfer(address(0), onBehalfOf, amount);
        return true;
    }

    /// @inheritdoc IAToken
    function burn(
        address from,
        address,
        uint256 amount,
        uint256
    ) external virtual override onlyPool {
        require(amount != 0, "mint zero amount");
        require(from != address(0), "ERC20: mint to the zero address");
        // console2.log(amount, "burn amount");

        // console2.log(_userState[from].balance, "burn before updatedBalance");
        _updateBalance(from);
        // console2.log(_userState[from].balance, "burn before balance");

        if(_totalSupply.balance < amount){
            // console2.log(_totalSupply.balance, "totalSupply");
            // console2.log(amount, "amount");
            revert("ATokenMock: burn to exceeded totalSupply");
        }
        if(_userState[from].balance < amount){
            // console2.log(_userState[from].balance, "balance");
            // console2.log(amount, "amount");
            revert("ATokenMock: burn to exceeded balance");
        }
        _totalSupply.balance -= amount;
        _userState[from].balance -= amount;
        // console2.log(_userState[from].balance, "burn after balance");
        // console2.log(balanceOf(from), "burn after balanceOf");

        emit Transfer(from, address(0), amount);
    }


    /// @inheritdoc IAToken
    function transferUnderlyingTo(address target, uint256 amount) external virtual override onlyPool {
        IERC20(_underlyingAsset).safeTransfer(target, amount);
    }

    /* ========== UNUSED FUNCTIONS ========== */

    /// @inheritdoc IAToken
    function mintToTreasury(uint256, uint256) external override onlyPool {}

    /// @inheritdoc IAToken
    function transferOnLiquidation(
        address,
        address,
        uint256
    ) external override onlyPool {}

    /// @inheritdoc IAToken
    function handleRepayment(address, uint256) external virtual override onlyPool {
        // Intentionally left blank
    }

    /// @inheritdoc IAToken
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external {}

    /// @inheritdoc IAToken
    function RESERVE_TREASURY_ADDRESS() external view override returns (address) {}

    /// @inheritdoc IAToken
    function DOMAIN_SEPARATOR() external view returns (bytes32) {}

    /// @inheritdoc IAToken
    function nonces(address owner) external view returns (uint256) {}

    /// @inheritdoc IAToken
    function permit(
        address,
        address,
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) external {}

}
