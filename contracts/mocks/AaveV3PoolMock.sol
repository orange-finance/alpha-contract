// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

import "../interfaces/IAaveV3Pool.sol";
import "./ATokenMock.sol";
import "./DebtTokenMock.sol";
import "./ERC20Mock.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "forge-std/console2.sol";

contract AaveV3PoolMock is IAaveV3Pool, Ownable {
    using SafeERC20 for IERC20;

    error OnlyVariable();
    error SameBlockBorrowRepay();

    event DeployedAsset(address AToken, address VDebtToken, address SDebtToken);

    modifier onlyVariable(uint256 interestRateMode) {
        if (interestRateMode != 2) revert OnlyVariable();
        _;
    }

    // underlyingAsset => aave's token
    mapping(address => IAToken) public aTokens;
    mapping(address => IVariableDebtToken) public vDebtTokens;
    mapping(address => IERC20) public sDebtTokens; // supposed to be unused
    // underlyingAsset => normalized interest at 1e25
    struct NormalizedRate {
        uint256 _rate;
        uint40 _startTimestamp;
    }
    mapping(address => NormalizedRate) public normalizedIncomesRate;
    mapping(address => NormalizedRate) public normalizedVariableDebtsRate;
    uint256 latestBorrowed; // used to restrict borrow and repay at same block

    function deployAssets(
        address _underlyingAsset,
        uint256 _normalizedIncomeRate,
        uint256 _normalizedVariableDebtRate
    ) external onlyOwner {
        uint8 _decimal = IERC20Metadata(_underlyingAsset).decimals();
        string memory _name = IERC20Metadata(_underlyingAsset).name();
        string memory _aName = string(abi.encodePacked("a", _name));
        string memory _vDebtName = string(abi.encodePacked("vDebt", _name));
        string memory _sDebtName = string(abi.encodePacked("sDebt", _name));

        aTokens[_underlyingAsset] = new ATokenMock(
            _underlyingAsset,
            IAaveV3Pool(address(this)),
            _decimal,
            _aName,
            _aName
        );
        vDebtTokens[_underlyingAsset] = new DebtTokenMock(
            _underlyingAsset,
            IAaveV3Pool(address(this)),
            _decimal,
            _vDebtName,
            _vDebtName
        );
        // supposed to be unused
        sDebtTokens[_underlyingAsset] = new ERC20Mock(
            _sDebtName,
            _sDebtName,
            _decimal
        );

        normalizedIncomesRate[_underlyingAsset] = NormalizedRate(
            _normalizedIncomeRate,
            uint40(block.timestamp)
        );
        normalizedVariableDebtsRate[_underlyingAsset] = NormalizedRate(
            _normalizedVariableDebtRate,
            uint40(block.timestamp)
        );
        emit DeployedAsset(
            address(aTokens[_underlyingAsset]),
            address(vDebtTokens[_underlyingAsset]),
            address(sDebtTokens[_underlyingAsset])
        );
    }

    /**
     * Ownable functions
     */
    function setNormalizedIncome(address _asset, uint256 _income)
        external
        onlyOwner
    {
        normalizedIncomesRate[_asset] = NormalizedRate(
            _income,
            uint40(block.timestamp)
        );
    }

    function setNormalizedVariableDebt(address _asset, uint256 _debt)
        external
        onlyOwner
    {
        normalizedVariableDebtsRate[_asset] = NormalizedRate(
            _debt,
            uint40(block.timestamp)
        );
    }

    /**
     * Inherit functions
     */
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external {
        IERC20(asset).safeTransferFrom(onBehalfOf, address(this), amount);
        aTokens[asset].mint(address(0), onBehalfOf, amount, 0);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        IERC20(asset).safeTransfer(to, amount);
        aTokens[asset].burn(msg.sender, address(0), amount, 0);

        return amount;
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16,
        address
    ) external onlyVariable(interestRateMode) {
        // TODO adding borrow cap by collateral
        // if (collateral < (((borrow + amount) * COLLATERAL_RATIO) / 100)) revert CollateralCannotCoverNewBorrow();

        IERC20(asset).safeTransfer(msg.sender, amount);
        vDebtTokens[asset].mint(address(0), msg.sender, amount, 0);
        latestBorrowed = block.timestamp;
    }

    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address
    ) external onlyVariable(interestRateMode) returns (uint256) {
        // restriction of supply and borrow at same block
        if (latestBorrowed == block.timestamp) revert SameBlockBorrowRepay();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        vDebtTokens[asset].burn(msg.sender, amount, 0);
        return amount;
    }

    function repayWithATokens(
        address asset,
        uint256 amount,
        uint256 interestRateMode
    ) external returns (uint256) {}

    ///@notice unused
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {}

    function getReserveNormalizedIncome(address asset)
        external
        view
        returns (uint256)
    {
        NormalizedRate memory rate = normalizedIncomesRate[asset];
        return 1e27 + (rate._rate * (block.timestamp - rate._startTimestamp));
    }

    function getReserveNormalizedVariableDebt(address asset)
        external
        view
        returns (uint256)
    {
        NormalizedRate memory rate = normalizedVariableDebtsRate[asset];
        return 1e27 + (rate._rate * (block.timestamp - rate._startTimestamp));
    }

    ///@notice unused
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {}

    function getReserveData(address asset)
        external
        view
        returns (DataTypes.ReserveData memory reserveData_)
    {
        DataTypes.ReserveConfigurationMap memory configuration;
        reserveData_ = DataTypes.ReserveData(
            configuration,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            address(aTokens[asset]),
            address(sDebtTokens[asset]),
            address(vDebtTokens[asset]),
            address(0),
            0,
            0,
            0
        );
    }
}
