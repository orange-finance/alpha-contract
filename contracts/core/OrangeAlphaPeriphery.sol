// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import {IOrangeAlphaVault} from "../interfaces/IOrangeAlphaVault.sol";
import {IOrangeAlphaParameters} from "../interfaces/IOrangeAlphaParameters.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IResolver} from "../vendor/gelato/IResolver.sol";

// import "forge-std/console2.sol";
// import {Ints} from "../mocks/Ints.sol";

contract OrangeAlphaPeriphery is IResolver {
    using SafeERC20 for IERC20;

    /* ========== STRUCTS ========== */
    struct DepositType {
        uint256 assets;
        uint40 timestamp;
    }

    /* ========== STORAGES ========== */
    mapping(address => DepositType) public deposits;
    uint256 public totalDeposits;

    /* ========== PARAMETERS ========== */
    IOrangeAlphaVault vault;
    IOrangeAlphaParameters params;

    /* ========== CONSTRUCTOR ========== */
    constructor(address _vault, address _params) {
        vault = IOrangeAlphaVault(_vault);
        params = IOrangeAlphaParameters(_params);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */
    function deposit(
        uint256 _assets,
        uint256 _minShares,
        bytes32[] calldata merkleProof
    ) external returns (uint256) {
        //validation of merkle proof
        _isAllowlisted(msg.sender, merkleProof);

        //validation of deposit caps
        if (deposits[msg.sender].assets + _assets > params.depositCap()) {
            revert("CAPOVER");
        }
        deposits[msg.sender].assets += _assets;
        deposits[msg.sender].timestamp = uint40(block.timestamp);
        uint256 _totalDeposits = totalDeposits;
        if (_totalDeposits + _assets > params.totalDepositCap()) {
            revert("CAPOVER");
        }
        totalDeposits = _totalDeposits + _assets;

        //transfer USDC
        vault.token1().safeTransferFrom(msg.sender, address(this), _assets);
        return vault.deposit(_assets, msg.sender, _minShares);
    }

    function redeem(uint256 _shares, uint256 _minAssets)
        external
        returns (uint256)
    {
        if (
            block.timestamp <
            deposits[msg.sender].timestamp + params.lockupPeriod()
        ) {
            revert("LOCKUP");
        }
        uint256 _assets = vault.redeem(
            _shares,
            msg.sender,
            msg.sender,
            _minAssets
        );

        //subtract depositsCap
        uint256 _deposited = deposits[msg.sender].assets;
        if (_deposited < _assets) {
            deposits[msg.sender].assets = 0;
        } else {
            unchecked {
                deposits[msg.sender].assets -= _assets;
            }
        }
        if (totalDeposits < _assets) {
            totalDeposits = 0;
        } else {
            unchecked {
                totalDeposits -= _assets;
            }
        }
        return _assets;
    }

    // @inheritdoc IResolver
    function checker()
        external
        view
        override
        returns (bool canExec, bytes memory execPayload)
    {
        IUniswapV3Pool _pool = vault.pool();
        (, int24 _currentTick, , , , , ) = _pool.slot0();
        int24 _twap = _getTwap();
        if (
            !vault.canStoploss(
                _currentTick,
                vault.stoplossLowerTick(),
                vault.stoplossUpperTick()
            ) ||
            !vault.canStoploss(
                _twap,
                vault.stoplossLowerTick(),
                vault.stoplossUpperTick()
            )
        ) {
            return (false, bytes("can not stoploss"));
        }
        execPayload = abi.encodeWithSelector(
            IOrangeAlphaVault.stoploss.selector,
            _twap
        );
        return (true, execPayload);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _isAllowlisted(address _account, bytes32[] calldata _merkleProof)
        internal
        view
    {
        if (params.allowlistEnabled()) {
            if (
                !MerkleProof.verify(
                    _merkleProof,
                    params.merkleRoot(),
                    keccak256(abi.encodePacked(_account))
                )
            ) {
                revert("MERKLE_ALLOWLISTED");
            }
        }
    }

    function _getTwap() internal view virtual returns (int24 avgTick) {
        IUniswapV3Pool _pool = vault.pool();

        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = 5 minutes;
        secondsAgo[1] = 0;

        (int56[] memory tickCumulatives, ) = _pool.observe(secondsAgo);

        require(tickCumulatives.length == 2, "array len");
        unchecked {
            avgTick = int24(
                (tickCumulatives[1] - tickCumulatives[0]) /
                    int56(uint56(5 minutes))
            );
        }
    }
}
