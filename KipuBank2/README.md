# KipuBankV2

This document contains an upgraded `KipuBankV2.sol` contract (production-minded refactor of the original KipuBank) and a README describing the design decisions, deployment notes and how to interact with the contract.

---

A multi-token banking vault (ETH + any ERC-20)
A strict deposit cap expressed in USD using Chainlink Data Feeds
Decimal-aware value conversion for accurate USD accounting
An ERC721 NFT collection that can be minted by paying with:
ERC-20 token (configurable, e.g. USDC)
ETH (fixed price)
BTC-equivalent value (converted on-chain via BTC/ETH oracle)


All deposits are tracked in USD (18-decimal normalized scale) so the bank never exceeds the immutable bankCapInUsd.

# Key Features
| Feature                                   | Implementation                                                                 |
|-------------------------------------------|---------------------------------------------------------------------------------|
| Multi-token deposits (ETH + ERC-20)       | `deposit(address token, uint256 amount)`                                        |
| USD-based bank cap                        | `bankCapInUsd` + Chainlink ETH/USD feed                                         |
| Decimal conversion utility                | `convertToDecimals()` + `IERC20Metadata` usage                                  |
| Reentrancy protection                     | OpenZeppelin `ReentrancyGuard`                                                  |
| Withdrawal limit (10 ETH per tx)          | Immutable `WITHDRAWAL_LIMIT`                                                    |
| Three minting methods                     | `mintWithToken()`, `mintWithETH()`, `mintWithBTC()`                             |
| Full NatSpec documentation               | All public/external functions documented with `@notice`, `@dev`, `@param`, `@return` |
| Custom errors                             | Gas-efficient error handling using `error` keyword                             |
| Events for full on-chain transparency     | `DepositedToken`, `Pulled`, mint events, `PriceUpdated`, `FallbackCalled`, etc. |

# Design Decisions & Trade-offs

- OnlyOwner instead of Roles – kept simple for the scope of the final project while still allowing easy extension.
- USD accounting currently supports ETH (dynamic) and any stablecoin with a 1:1 peg (e.g., USDC) via decimal normalization.
- Original KipuBank autenticity manteined

## Deployed Contract (Sepolia Testnet)

**Address:** `0x01C056e6a42950Da75A756A2c2EdDD8A19ECE51c`

https://sepolia.etherscan.io/address/0x01C056e6a42950Da75A756A2c2EdDD8A19ECE51c

### Verification Links
- Sourcify → https://repo.sourcify.dev/11155111/0x01C056e6a42950Da75A756A2c2EdDD8A19ECE51c/
- Routescan → https://testnet.routescan.io/address/0x01C056e6a42950Da75A756A2c2EdDD8A19ECE51c
- Blockscout → https://eth-sepolia.blockscout.com/address/0x01C056e6a42950Da75A756A2c2EdDD8A19ECE51c?tab=contract
