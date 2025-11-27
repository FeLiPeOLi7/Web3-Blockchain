# KipuBankV2

This document contains an upgraded `KipuBankV2.sol` contract (production-minded refactor of the original KipuBank) and a README describing the design decisions, deployment notes and how to interact with the contract.

---

## File: `contracts/KipuBankV2.sol`

### High-level improvements

* **Role-based access control** using OpenZeppelin `AccessControl` instead of single `owner` address. This allows separation of duties (admin, operator) and safer key management.
* **Multi-token support** with nested mappings `balances[token][user]` and `totalDepositsPerToken[token]` so multiple assets can be tracked simultaneously.
* **Chainlink price feeds**: tokens must be registered together with a Chainlink USD price feed. This allows an USD-denominated `bankCap` and consistent cross-token accounting.
* **USD-denominated cap and accounting**: bank cap and `totalDepositsUSD` use the price feed decimals (commonly 8). Deposits that would exceed the cap revert.
* **Safe token transfers** via `SafeERC20` and `ReentrancyGuard` applied to mutating entry points.
* **Checks-Effects-Interactions**: state is updated before external calls.
* **Integrity check**: admin-only function to verify on-chain balances match internal accounting.
* **Emergency withdrawal** for admin in case of critical failures.

### Deployment & Interaction

1. Deploy `KipuBankV2` with initial `bankCapUSD` (example: `1_000_000 * 1e8` for $1,000,000 if feed uses 8 decimals).
2. As admin, register tokens you will accept using `registerToken(tokenAddress, decimals, priceFeedAddress)`.

   * For ETH: `tokenAddress = address(0)`, `decimals = 18`, `priceFeed = ETH/USD Chainlink feed`.
   * For ERC20: pass the token decimals and the USD price feed for that token.
3. Users deposit by calling `deposit(token, amount)`.

   * For ETH deposits: call `deposit(address(0), msg.value)`.
   * For ERC20 deposits: `approve` this contract then call `deposit(token, amount)`.
4. Users withdraw via `withdraw(token, amount)`.
5. Use `checkIntegrity([tokens...])` to ensure recorded totals match actual contract balances.

### Notes on design decisions & trade-offs

* **Price feed granularity**: The contract trusts Chainlink feeds provided at registration. Make sure feeds are correct and have sufficient freshness — no feed staleness checks are included in this minimal example (you can add `updatedAt` checks).
* **USD scaling**: USD values use the price feed decimals (commonly `1e8`). All USD arithmetic is performed in those units to avoid repeated conversions; frontends should be made aware of this scaling.
* **Decimals handling**: Admin must provide correct token decimals. For production, you can attempt to read `decimals()` from the token contract (`IERC20Metadata`) but some tokens may not implement it — explicit registration is safer.
* **Direct ETH transfers**: `receive()` is implemented but discouraged — prefer explicit `deposit(address(0), msg.value)` to ensure accounting and event emission.
* **Gas vs functionality**: The contract prioritizes clarity and safety over aggressive gas micro-optimizations. In production, consider packing, using immutable variables where appropriate, and reducing storage writes.

### Verification & Testnet

* Verify source on a testnet explorer (Etherscan / polygonscan). Provide constructor args: `bankCapUSD`.
* After verifying, register tokens and publish a short deployment/interaction script using Hardhat or Foundry.

---

If you want, I can:

* extract the `KipuBankV2.sol` file into a separate code file in the repository structure (`/src/contracts/KipuBankV2.sol`),
* produce a Hardhat deployment script and example tests,
* add staleness checks for Chainlink feeds and more granular withdrawal limits per token.
