# 🛡️ THREAT ANALYSIS AND INVARIANT SPECIFICATION REPORT

## (Relatório de Análise de Ameaças e Especificação de Invariantes)

1. Protocol Overview: KipuBankV3

The KipuBankV3 protocol is a hybrid smart contract designed to serve two primary functions: an ERC721 NFT minting platform and a Multi-Token Custodial Bank. It integrates with essential external services for both security and functionality.

2. Protocol Maturity Assessment

The contract has a solid foundation (using established libraries like OpenZeppelin and external DeFi protocols) but requires significant effort to achieve production readiness.

| Aspect           | Status           | Weaknesses / Missing Steps |
|-----------------|----------------|----------------------------|
| Test Coverage    | Low / Incomplete | Lacks comprehensive Fuzz Testing and Invariant Testing. The critical _swapArbitraryTokenToUSDC logic requires extensive mocking and scenario testing for various fees and slippage. |
| Testing Methods  | Unit Tests Only | Must implement Fork Testing (using Foundry/Anvil) to test against a live mainnet state and verify correct interaction with the Universal Router and real liquidity pools. |
| Documentation    | Functional      | Good NatSpec comments |
| Roles & Powers   | Centralized     | The Owner role is omnipotent. The Owner is responsible for setting prices, activating the sale, and crucially, pre-approving the Universal Router. This centralization is a single point of failure. In the future the project could have a MINTER_ROLE or a ADMIN_ROLE |
| Invariants       | Not Specified   | No formal invariant properties have been defined and validated with property testing. |


3. Threat Vectors and Threat Model

It has been identified four critical attack surfaces across logic, economics, and permissions.
3.1. Attack Vector: Missing Oracle Stale Check (Logic/Economic)

    Surface: depositArbitraryToken (Case 1: ETH deposit) relies on getEthPriceInUsd().

    Scenario: A critical price change event occurs (e.g., massive price crash), and the Chainlink oracle fails to update or is deliberately paused. The function retrieves old (stale) data.

    Impact: A user can deposit a small amount of ETH, but the contract's _toUsd function (and consequently totalDepositsInUsd) will use the stale, high price to calculate the USD value, effectively over-crediting the user's USD balance. This inflation can also incorrectly trigger the BankCapReached error for legitimate users or allow the attacker to claim a disproportionately large share of the bank's capacity.

    Mitigation Missing: The Chainlink functions lack a check on the updatedAt timestamp to ensure the data is not older than a maximum threshold (e.g., 3 hours).


3.2. Attack Vector: Swap Slippage Exploitation (Economic)

    Surface: _swapArbitraryTokenToUSDC logic.

    Scenario: A user initiates a large depositArbitraryToken of a low-liquidity token, triggering the swap to USDC. A malicious actor observes this transaction and front-runs it by executing two transactions (a Sandwich Attack) that move the pool price against the user.

    Impact: The swap results in a very low amountOut of USDC for the user. While the user is protected from complete loss by the amountOut == 0 check, the crucial line is: minAmountOut: 1. Hardcoding minAmountOut to 1 provides virtually zero protection against slippage and MEV, allowing the MEV bots to extract maximum profit from the user's transaction.

    Mitigation Missing: The protocol must allow the user to define a maximum acceptable slippage tolerance (minAmountOut) or set a tighter, dynamically calculated tolerance.


3.3. Attack Vector: Accounting Mismatch and Integrity Bypass (Logic Error)

    Surface: checkIntegrity() function.

    Scenario: A user successfully deposits an arbitrary token, which is converted to USDC. The accounting updates: balances[user][USDC] increases, and totalDepositsInUsd increases.

    Impact: The checkIntegrity() function is implemented as: if (realBalance != totalDeposits - totalWithDrawal) revert BalanceMismatch();.

        realBalance refers only to address(this).balance (ETH).

        The contract now holds USDC (ERC20 tokens), which are not included in address(this).balance.

        totalDeposits is only updated when ETH is deposited (Case 1) but not for ERC20s (Case 2 and 3). This seems like a V2 legacy error.

        Crucially: The function will always fail/revert as soon as the contract holds any USDC or any accounting variable is updated (which happens frequently). This renders the checkIntegrity useless and creates a maintenance risk.

    Mitigation: The integrity check must be redesigned to sum up the USD-equivalent value of all token balances held by the contract (ETH, USDC, and any residual tokens) and compare that sum to totalDepositsInUsd.

4. Specification of Invariants

Invariants are properties that must remain true for the duration of the contract's lifecycle.

    I-01	Bank Capacity Cap: totalDepositsInUsd must always be less than or equal to bankCapInUsd.	Ensures the protocol adheres to its maximum defined exposure limit.
    
    I-02	Token Conservation (After Swap): For any call to depositArbitraryToken(TOKEN_A, amountIn), the final contract balance of USDC must be greater than the initial contract balance of USDC by amountOut. Concurrently, the final contract balance of TOKEN_A must equal the initial contract balance of TOKEN_A (i.e., amountIn must have been fully spent by the router).	Validates the core logic of the Universal Router integration: tokens in are swapped for tokens out, with no residual input token left unaccounted for.
    
    I-03	NFT Supply Limit: tokenCurrentSupply_ must always be less than or equal to maxSupply.	Guarantees the scarcity and integrity of the ERC721 collection.
    
    I-04	Balance Non-Negativity: For all users U and all tokens T, balances[U][T] must be greater than or equal to zero.	Prevents potential underflow exploits or incorrect accounting that leads to negative balances.

5. Impact of Invariant Violations

    I-01 (Cap)	Allows the protocol to exceed its defined capital limits, creating systemic risk and potential regulatory exposure.	This is a great risk, because the bank cannot surpass the bankCapInUSDC.
    
    I-02 (Conservation)	Critical Loss of Funds: Indicates that the Universal Router call failed partially, an internal token transfer failed, or a slippage exploit occurred, leading to a loss of user funds or residual input tokens stuck in the contract. 

    I-03 (Scarcity) If a token surpass his maxSupply, could be potentially dangerous for the bank, because could inflationate the price of the token.
    
    I-04 (Non-Negativity)	If a balance becomes negative (due to an underflow during withdrawal), it allows the user to withdraw an arbitrary, massive amount of funds from the contract's reserves (Theft).

6. Recommendations and Validation

    1. Oracle Security	Implement Stale Data Checks in getEthPriceInUsd() and getBTCEthPrice(). Revert if updatedAt is older than, e.g., 3 hours.	
    
    2. Remove Hardcoded Slippage: Modify _swapArbitraryTokenToUSDC to accept a dynamic minAmountOut parameter, calculated by the user's front-end based on a max slippage tolerance (e.g., 0.5%).	
    
    3. Invariant Testing to ensure I-01, I-02, and I-04 are never violated across thousands of random deposit/pull/mint operations.
    
    4. Make more roles to not have a single point of failure (owner).

7. Conclusion and Next Steps

The KipuBankV3 has advanced integration with Chainlink and Uniswap, but it is not ready for mainnet launch. The primary blockers are the lack of slippage protection in the swap logic and the vulnerability to stale oracle data.

