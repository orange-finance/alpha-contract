// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.16;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IStrategy} from "@src/coreV2/vault/IStrategy.sol";

contract TokenizedStrategyImpl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 constant SHARED_STORAGE = bytes32(uint256(keccak256("orange.shared.storage")) - 1);

    struct SharedStorage {
        IERC20 asset;
        uint8 decimals;
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 depositCap;
        bool allowlistEnabled;
        bytes32 merkleRoot;
        uint256 minDepositAmount;
        mapping(address => uint256) nonces;
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    error AmountZero();
    error LessThanMinDepositAmount();
    error DepositCapReached();
    error WithdrawnLessThanMinAsset();

    function _sharedStorage() internal pure returns (SharedStorage storage s) {
        bytes32 slot = SHARED_STORAGE;
        assembly {
            s.slot := slot
        }
    }

    // view
    function convertToShares(uint256 assets) public returns (uint256) {
        SharedStorage storage s = _sharedStorage();

        uint256 _totalSupply = s.totalSupply;

        if (_totalSupply == 0) return assets;

        return assets.mulDiv(_totalSupply, IStrategy(address(this)).totalAssets());
    }

    function convertToAssets(uint256 shares) external returns (uint256 assets) {
        SharedStorage storage s = _sharedStorage();

        uint256 _totalSupply = s.totalSupply;

        if (_totalSupply == 0) return shares;

        return shares.mulDiv(IStrategy(address(this)).totalAssets(), _totalSupply);
    }

    // state modifying
    function deposit(
        uint256 assets,
        bytes32[] calldata merkleProof,
        bytes calldata depositConfig
    ) external returns (uint256) {
        SharedStorage storage s = _sharedStorage();

        if (assets == 0) revert AmountZero();
        if (assets < s.minDepositAmount) revert LessThanMinDepositAmount();

        // only first deposit
        if (s.totalSupply == 0) return _firstDeposit(s, assets);

        uint256 _totalAssets = IStrategy(address(this)).totalAssets();
        if (_totalAssets + assets > s.depositCap) revert DepositCapReached();

        s.asset.safeTransferFrom(msg.sender, address(this), assets);

        IStrategy(address(this)).depositCallback(assets, depositConfig);

        _mint(msg.sender, share);

        return share;
    }

    function redeem(uint256 share, uint256 minAssets, bytes calldata redeemConfig) external returns (uint256) {
        SharedStorage storage s = _sharedStorage();

        if (share == 0) revert AmountZero();

        uint256 _assets = convertToAssets(share);

        uint256 _beforeBal = s.asset.balanceOf(address(this));
        IStrategy(address(this)).withdrawCallback(assets, redeemConfig);
        uint256 _afterBal = s.asset.balanceOf(address(this));

        uint256 _withdrawn = _afterBal - _beforeBal;

        if (_withdrawn < minAssets) revert WithdrawnLessThanMinAsset();

        _sharedStorage().asset.safeTransfer(msg.sender, _assets);

        _burn(msg.sender, share);

        return _withdrawn;
    }

    function tend(bytes calldata tendConfig) external {
        IStrategy(address(this)).tendThis(tendConfig);
    }

    function _firstDeposit(SharedStorage storage s, uint256 assets) internal returns (uint256) {
        s.asset.safeTransferFrom(msg.sender, address(this), assets);
        uint _initialBurnedBalance = (10 ** s.decimals / 1000);
        uint _share = assets - _initialBurnedBalance;
        _mint(msg.sender, _share);
        _mint(address(0), _initialBurnedBalance); // for manipulation resistance

        return _share;
    }

    /*//////////////////////////////////////////////////////////////
                                ERC20 functions
    //////////////////////////////////////////////////////////////*/
    function name() external view returns (string memory) {
        return _sharedStorage().name;
    }

    function symbol() external view returns (string memory) {
        return _sharedStorage().symbol;
    }

    function decimals() external view returns (uint8) {
        return _sharedStorage().decimals;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _sharedStorage().balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _sharedStorage().allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, allowance(owner, spender) - subtractedValue);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(to != address(this), "ERC20 transfer to strategy");
        SharedStorage storage s = _sharedStorage();

        s.balances[from] -= amount;
        unchecked {
            s.balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) private {
        require(account != address(0), "ERC20: mint to the zero address");
        SharedStorage storage S = _sharedStorage();

        S.totalSupply += amount;
        unchecked {
            S.balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) private {
        require(account != address(0), "ERC20: burn from the zero address");
        SharedStorage storage S = _sharedStorage();

        S.balances[account] -= amount;
        unchecked {
            S.totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _sharedStorage().allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}
