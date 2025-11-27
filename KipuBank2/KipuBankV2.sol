// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @notice Multi-token bank with role-based access control, Chainlink price feeds and USD-denominated bank cap.
 * - Supports ETH (token == address(0)) and any ERC20 token registered by admin.
 * - Internal accounting per token: balances[token][user].
 * - Totals and bank-cap are tracked in USD (using Chainlink price feeds) with feed decimals for precision.
 * - Uses OpenZeppelin AccessControl for admin/operator roles.
 * - Uses SafeERC20 for safe token transfers and ReentrancyGuard.
 */
contract KipuBankV2 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ========== ROLES ========== */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /* ========== ERRORS ========== */    
    error NotAdmin();
    error ZeroAmount();
    error UnsupportedToken(address token);
    error BankCapReached(uint256 capUSD, uint256 attemptedUSD);
    error InsufficientBalance(address token, address user, uint256 available, uint256 requested);
    error TransferFailed();
    error InvalidAddress();

    /* ========== EVENTS ========== */
    event TokenRegistered(address indexed token, uint8 decimals, address priceFeed);
    event TokenUpdated(address indexed token, uint8 decimals, address priceFeed);
    event Deposited(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event Withdrawn(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event BankCapUpdated(uint256 newCapUSD);
    event EmergencyWithdraw(address indexed to, address indexed token, uint256 amount);

    /* ========== STRUCTS ========== */
    struct TokenInfo {
        bool enabled;
        uint8 decimals; // token decimals (for ERC20). For ETH token (address(0)) use 18.
        address priceFeed; // Chainlink price feed that returns price in USD with feedDecimals (commonly 8)
    }

    // token => user => balance (in token base units)
    mapping(address => mapping(address => uint256)) public balances;

    // token => total deposited (in token base units)
    mapping(address => uint256) public totalDepositsPerToken;

    // token => TokenInfo
    mapping(address => TokenInfo) public tokenInfo;

    // bank cap in USD scaled by 1e8 (we will keep Chainlink feed convention: many feeds use 8 decimals)
    uint256 public bankCapUSD; // e.g. 1_000_000 * 1e8 => 1,000,000 USD with 8 decimals

    // total deposits across tokens expressed in USD (scaled by feed decimals)
    uint256 public totalDepositsUSD;

    // immutable admin set at deploy
    address public immutable deployer;

    constructor(uint256 _bankCapUSD) {
        deployer = msg.sender;
        bankCapUSD = _bankCapUSD;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }

    /* ========== ADMIN / OPERATOR FUNCTIONS ========== */

    /// @notice Register a token and its price feed and decimals. For ETH, use token == address(0) and decimals = 18.
    function registerToken(address token, uint8 decimals, address priceFeed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (priceFeed == address(0)) revert InvalidAddress();
        tokenInfo[token] = TokenInfo({enabled: true, decimals: decimals, priceFeed: priceFeed});
        emit TokenRegistered(token, decimals, priceFeed);
    }

    function updateToken(address token, uint8 decimals, address priceFeed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!tokenInfo[token].enabled) revert UnsupportedToken(token);
        tokenInfo[token].decimals = decimals;
        tokenInfo[token].priceFeed = priceFeed;
        emit TokenUpdated(token, decimals, priceFeed);
    }

    function setBankCapUSD(uint256 newCapUSD) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bankCapUSD = newCapUSD;
        emit BankCapUpdated(newCapUSD);
    }

    /* ========== CORE: DEPOSIT / WITHDRAW ========== */

    /// @notice Deposit ERC20 token or ETH (token == address(0)). For ERC20, caller must approve this contract.
    /// @param token The token address (address(0) for ETH).
    /// @param amount Amount to deposit in token base units. For ETH, `amount` must equal `msg.value`.
    function deposit(address token, uint256 amount) external payable nonReentrant {
        if (amount == 0) revert ZeroAmount();
        TokenInfo memory info = tokenInfo[token];
        if (!info.enabled) revert UnsupportedToken(token);

        // accept ETH
        if (token == address(0)) {
            // ETH deposit
            if (msg.value != amount) revert ZeroAmount();
        } else {
            // ERC20: pull tokens
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // compute USD value (scaled by feed decimals)
        uint256 usdValue = _toUSD(token, amount);

        // check bank cap
        uint256 newTotalUSD = totalDepositsUSD + usdValue;
        if (newTotalUSD > bankCapUSD) revert BankCapReached(bankCapUSD, newTotalUSD);

        // EFFECTS
        balances[token][msg.sender] += amount;
        totalDepositsPerToken[token] += amount;
        totalDepositsUSD = newTotalUSD;

        emit Deposited(msg.sender, token, amount, usdValue);
    }

    /// @notice Withdraw token or ETH
    function withdraw(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        TokenInfo memory info = tokenInfo[token];
        if (!info.enabled) revert UnsupportedToken(token);

        uint256 userBal = balances[token][msg.sender];
        if (userBal < amount) revert InsufficientBalance(token, msg.sender, userBal, amount);

        // compute USD value to keep totals consistent
        uint256 usdValue = _toUSD(token, amount);

        // EFFECTS
        balances[token][msg.sender] = userBal - amount;
        totalDepositsPerToken[token] -= amount;
        // guard underflow: totalDepositsUSD >= usdValue assumed by accounting
        totalDepositsUSD -= usdValue;

        // INTERACTIONS: transfer after effects
        if (token == address(0)) {
            (bool ok,) = payable(msg.sender).call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Withdrawn(msg.sender, token, amount, usdValue);
    }

    /* ========== VIEW HELPERS ========== */

    /// @notice Convert token amount to USD using registered price feed.
    /// @dev Returns USD value scaled by the feed's decimals (commonly 1e8).
    function _toUSD(address token, uint256 amount) internal view returns (uint256) {
        TokenInfo memory info = tokenInfo[token];
        if (!info.enabled) revert UnsupportedToken(token);
        AggregatorV3Interface feed = AggregatorV3Interface(info.priceFeed);
        (, int256 price,, ,) = feed.latestRoundData();
        if (price <= 0) revert("Invalid price from feed");

        uint8 feedDecimals = feed.decimals();
        uint8 tokenDecimals = info.decimals;

        // usdValue = amount * price / (10 ** tokenDecimals)
        // price has feedDecimals, so usdValue is scaled by feedDecimals
        uint256 amt = amount;
        uint256 p = uint256(price);

        // Calculate: (amount * price) / (10 ** tokenDecimals)
        // Be mindful of overflow: Solidity ^0.8 has safe math.
        uint256 usdValue = (amt * p) / (10 ** tokenDecimals);
        return usdValue; // scaled by feedDecimals
    }

    /// @notice Get user's balance for a token
    function balanceOf(address token, address user) external view returns (uint256) {
        return balances[token][user];
    }

    /// @notice Returns contract's token balance (ERC20) or ETH balance when token==address(0)
    function contractTokenBalance(address token) external view returns (uint256) {
        if (token == address(0)) return address(this).balance;
        return IERC20(token).balanceOf(address(this));
    }

    /* ========== INTEGRITY & EMERGENCY ========== */

    /// @notice Sanity check that internal accounting (per-token totals) matches on-chain holdings.
    /// @dev Only admin can call.
    function checkIntegrity(address[] calldata tokens) external view onlyRole(DEFAULT_ADMIN_ROLE) returns (bool ok) {
        for (uint256 i = 0; i < tokens.length; i++) {
            address t = tokens[i];
            TokenInfo memory info = tokenInfo[t];
            if (!info.enabled) revert UnsupportedToken(t);
            uint256 onChain = t == address(0) ? address(this).balance : IERC20(t).balanceOf(address(this));
            uint256 recorded = totalDepositsPerToken[t];
            if (onChain != recorded) return false;
        }
        return true;
    }

    /// @notice Emergency: withdraw tokens/ETH to admin. Should be used only in emergencies.
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();

        if (token == address(0)) {
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) revert TransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }

        emit EmergencyWithdraw(to, token, amount);
    }

    /* ========== FALLBACK / RECEIVE ========== */
    receive() external payable {
        // accept ETH only if address(0) was registered
        if (!tokenInfo[address(0)].enabled) revert UnsupportedToken(address(0));
        // treat direct ETH transfer as deposit of msg.value for the sender
        // caller MUST call deposit(addr(0), msg.value) to ensure accounting; direct transfers are discouraged
    }
}