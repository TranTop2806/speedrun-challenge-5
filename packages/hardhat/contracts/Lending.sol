// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Corn.sol";
import "./CornDEX.sol";

error Lending__InvalidAmount();
error Lending__TransferFailed();
error Lending__UnsafePositionRatio();
error Lending__BorrowingFailed();
error Lending__RepayingFailed();
error Lending__PositionSafe();
error Lending__NotLiquidatable();
error Lending__InsufficientLiquidatorCorn();

contract Lending is Ownable {
    uint256 private constant COLLATERAL_RATIO = 120; // 120% collateralization required
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10% reward for liquidators

    Corn private i_corn;
    CornDEX private i_cornDEX;

    mapping(address => uint256) public s_userCollateral; // User's collateral balance
    mapping(address => uint256) public s_userBorrowed; // User's borrowed corn balance

    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    event CollateralWithdrawn(address indexed user, uint256 indexed amount, uint256 price);
    event AssetBorrowed(address indexed user, uint256 indexed amount, uint256 price);
    event AssetRepaid(address indexed user, uint256 indexed amount, uint256 price);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    constructor(address _cornDEX, address _corn) Ownable(msg.sender) {
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        // Approve is generally not needed here unless the contract trades its own Corn, 
        // but keeping it as per your template structure intent.
        i_corn.approve(address(this), type(uint256).max);
    }

    /**
     * @notice Allows users to add collateral to their account
     */
    function addCollateral() public payable {
        if (msg.value == 0) {
            revert Lending__InvalidAmount();
        }
        s_userCollateral[msg.sender] += msg.value;
        emit CollateralAdded(msg.sender, msg.value, getPrice());
    }

    /**
     * @notice Allows users to withdraw collateral as long as it doesn't make them liquidatable
     * @param amount The amount of collateral to withdraw
     */
    function withdrawCollateral(uint256 amount) public {
        if (amount == 0 || s_userCollateral[msg.sender] < amount) {
            revert Lending__InvalidAmount();
        }
        
        // 1. Reduce balance first (Checks-Effects-Interactions)
        s_userCollateral[msg.sender] -= amount;

        // 2. Check if position is still safe
        _validatePosition(msg.sender);

        // 3. Transfer ETH back to user
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Lending__TransferFailed();
        }

        emit CollateralWithdrawn(msg.sender, amount, getPrice());
    }

    /**
     * @notice Calculates the total collateral value for a user based on their collateral balance
     * @param user The address of the user to calculate the collateral value for
     * @return uint256 The collateral value in CORN
     */
    function calculateCollateralValue(address user) public view returns (uint256) {
        uint256 ethCollateral = s_userCollateral[user];
        if (ethCollateral == 0) return 0;
        
        uint256 price = getPrice(); 
        // Logic: (ETH Amount * Price) / 1e18 (to adjust decimals)
        return (ethCollateral * price) / 1e18;
    }

    /**
     * @notice Calculates the position ratio for a user to ensure they are within safe limits
     * @param user The address of the user to calculate the position ratio for
     * @return uint256 The position ratio
     */
    function _calculatePositionRatio(address user) internal view returns (uint256) {
        uint256 borrowed = s_userBorrowed[user];
        if (borrowed == 0) return type(uint256).max; // Infinite ratio if no debt

        uint256 collateralValue = calculateCollateralValue(user);
        
        // Formula: (CollateralValue * 100) / Borrowed
        // Using 100 to match COLLATERAL_RATIO = 120 (integers)
        return (collateralValue * 100) / borrowed;
    }

    /**
     * @notice Checks if a user's position can be liquidated
     * @param user The address of the user to check
     * @return bool True if the position is liquidatable, false otherwise
     */
    function isLiquidatable(address user) public view returns (bool) {
        return _calculatePositionRatio(user) < COLLATERAL_RATIO;
    }

    /**
     * @notice Internal view method that reverts if a user's position is unsafe
     * @param user The address of the user to validate
     */
    function _validatePosition(address user) internal view {
        if (isLiquidatable(user)) {
            revert Lending__UnsafePositionRatio();
        }
    }

    /**
     * @notice Allows users to borrow corn based on their collateral
     * @param borrowAmount The amount of corn to borrow
     */
    function borrowCorn(uint256 borrowAmount) public {
        if (borrowAmount == 0) {
            revert Lending__InvalidAmount();
        }

        s_userBorrowed[msg.sender] += borrowAmount;
        
        // Check health factor AFTER adding debt
        _validatePosition(msg.sender);

        bool success = i_corn.transfer(msg.sender, borrowAmount);
        if (!success) {
            revert Lending__BorrowingFailed();
        }

        emit AssetBorrowed(msg.sender, borrowAmount, getPrice());
    }

    /**
     * @notice Allows users to repay corn and reduce their debt
     * @param repayAmount The amount of corn to repay
     */
    function repayCorn(uint256 repayAmount) public {
        if (repayAmount == 0) {
            revert Lending__InvalidAmount();
        }
        if (s_userBorrowed[msg.sender] < repayAmount) {
            revert Lending__InvalidAmount(); // Trying to repay more than owed
        }

        s_userBorrowed[msg.sender] -= repayAmount;

        bool success = i_corn.transferFrom(msg.sender, address(this), repayAmount);
        if (!success) {
            revert Lending__RepayingFailed();
        }

        emit AssetRepaid(msg.sender, repayAmount, getPrice());
    }

    /**
     * @notice Allows liquidators to liquidate unsafe positions
     * @param user The address of the user to liquidate
     * @dev The caller must have enough CORN to pay back user's debt
     * @dev The caller must have approved this contract to transfer the debt
     */
    function liquidate(address user) public {
        // 1. Kiểm tra vị thế có thực sự bị thanh lý được không
        if (!isLiquidatable(user)) {
            revert Lending__NotLiquidatable();
        }

        uint256 debtToCover = s_userBorrowed[user];

        // --- ĐÂY LÀ PHẦN QUAN TRỌNG ĐỂ PASS TEST ---
        // Kiểm tra số dư CORN của người thanh lý (liquidator) trước
        if (i_corn.balanceOf(msg.sender) < debtToCover) {
            revert Lending__InsufficientLiquidatorCorn();
        }
        // ------------------------------------------

        uint256 price = getPrice();
        
        // Xóa nợ cho người vay
        s_userBorrowed[user] = 0;

        // Tính toán lượng ETH để thu hồi (Nợ + 10% thưởng)
        uint256 debtInEth = (debtToCover * 1e18) / price;
        uint256 reward = (debtInEth * LIQUIDATOR_REWARD) / 100;
        uint256 totalCollateralToSeize = debtInEth + reward;

        // Đảm bảo không lấy vượt quá số dư của user
        if (totalCollateralToSeize > s_userCollateral[user]) {
            totalCollateralToSeize = s_userCollateral[user];
        }

        // Thu hồi CORN từ người thanh lý
        bool successCorn = i_corn.transferFrom(msg.sender, address(this), debtToCover);
        if (!successCorn) {
            revert Lending__InsufficientLiquidatorCorn();
        }

        // Trả ETH thưởng cho người thanh lý
        s_userCollateral[user] -= totalCollateralToSeize;
        (bool successEth, ) = payable(msg.sender).call{value: totalCollateralToSeize}("");
        if (!successEth) {
            revert Lending__TransferFailed();
        }

        emit Liquidation(user, msg.sender, totalCollateralToSeize, debtToCover, price);
    }

    // Helper to get price cleanly
    function getPrice() internal view returns (uint256) {
        // Assuming CornDEX has a currentPrice() function based on standard challenge
        return i_cornDEX.currentPrice(); 
    }
}