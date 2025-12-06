# KipuBankV3: NFT Minting e Banco Híbrido com DeFi

O `KipuBankV3` é um contrato inteligente Solidity projetado para funcionar como um banco de custódia e uma plataforma de Minting de NFTs (ERC721). Ele combina o gerenciamento tradicional de saldos de usuários com integração avançada de Finanças Descentralizadas (DeFi) via Uniswap Universal Router.

## Propósito do Projeto

O objetivo principal deste contrato é:


1.  **Executar swaps de tokens dentro do contrato inteligente**

2.  **Preservar a funcionalidade do KipuBankV2**: mantendo o suporte a depósitos, saques, consultas de oráculos de preço e lógica do proprietário (owner).

3.  **Aplicar o limite do banco (Bank Cap)**

4.  **Integração DeFi (Universal Router):** Converter automaticamente qualquer token ERC20 depositado (que não seja USDC) em **USDC** através de um swap via **Uniswap Universal Router**.

## Funcionalidades Chave

### Depósitos e Contabilidade

A função principal de depósito (`depositArbitraryToken`) gerencia a entrada de fundos e a contabilidade do limite do banco (`bankCapInUsd`):

* **Depósito de ETH:** O valor em ETH é convertido para USD usando o **Chainlink ETH/USD Price Feed** e contabilizado contra o limite do banco.
* **Depósito de USDC:** O token é aceito diretamente, pois o USDC é a moeda de contabilidade primária do banco.
* **Depósito de Token Arbitrário:** O token de entrada (ex: WETH, DAI) é imediatamente **trocado (swapped)** por USDC usando o **Universal Router** da Uniswap. O valor do USDC recebido é então contabilizado.
* **Bank Cap:** O valor total de depósitos em USD (`totalDepositsInUsd`) é comparado com o limite máximo do banco (`bankCapInUsd`) para evitar excesso de custódia.

### Swap com Universal Router

A função interna `_swapArbitraryTokenToUSDC` (ou `_swapExactInputSingle`) utiliza o **Universal Router** para realizar um `V3_SWAP_EXACT_IN` (swap de entrada exata).

* Ele usa o token depositado como entrada e o USDC como saída, garantindo que todos os tokens sejam normalizados para USDC para a contabilidade interna.

### Minting de NFT

O contrato permite a cunhagem de NFTs através de três métodos de pagamento distintos, usando oráculos Chainlink para garantir a paridade de preços entre ETH, o token de pagamento e o BTC.

* **Oráculos:** O **Chainlink BTC/ETH Price Feed** é usado para calcular o valor de pagamento em ETH equivalente ao preço estabelecido em BTC.

### Segurança

* **`nonReentrant`:** O modificador `nonReentrant` é aplicado às funções críticas de depósito e saque para prevenir ataques de reentrada.
* **`onlyOwner`:** Funções administrativas (como `setPrices` e `setSaleActive`) são restritas ao proprietário do contrato.

### Sourcify verification successful.
https://repo.sourcify.dev/11155111/0xFAf8297A7AceEE176126d0F27E303F6eEBEAEf09/

### Routescan verification successful.

https://testnet.routescan.io/address/0xFAf8297A7AceEE176126d0F27E303F6eEBEAEf09/contract/11155111/code

### Blockscout verification successful.
https://eth-sepolia.blockscout.com/address/0xFAf8297A7AceEE176126d0F27E303F6eEBEAEf09?tab=contract
