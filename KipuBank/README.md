#### English

# KipuBank: Decentralized Ether Vault

KipuBank is a smart contract for the Ethereum network that functions as a decentralized vault for ETH deposits. It enforces security limits both at the individual deposit level (global cap) and at the withdrawal level (per-transaction limit), using Solidity security standards such as reentrancy protection and custom errors.

## Features

KipuBank offers the following core features:
  ETH deposit: Users can deposit ETH into individual vaults (mapped by address). 
  Bank Cap: Imposed during stake, limiting the total ETH the contract can receive. 
  Limited Withdrawal: Users can withdraw their ETH, but each withdrawal transaction is restricted to an immutable limit (WITHDRAWAL_LIMIT = 10 ETH).
  Transparent Accounting: Records each user's balance, total deposits, and transaction count. 
  Advanced Security: Implements lock-in protection and an internal audit function to verify the integrity of the contract balance vs. internal accounting.

## Deployment Instructions

1.Clone the Repository

Bash

git clone https://github.com/FeLiPeOLi7/Web3-Blockchain.git
cd KipuBank

2. Configuration (Hardhat/Foundry Example)
  Set your private keys and the URL of your RPC Testnet in an.env file.

3. Builder Arguments
  The KipuBank contract requires a single argument at the time of deployment:
    Parameter Type Description Example _bankCap uint256 The global hard cap of ETH that the contract can hold. 100 ether (10000000000000000000000000 wei)

## How to Interact with the Contract

Here are the main KipuBank functions and how to use them:

User Functions

Function	Visibility	Description	Example Usage
deposit()	external payable	Deposits ETH into the personal vault. Reverts if it exceeds the bankCap.	Call the function sending X ETH.
pull(uint256 amount)	external	Withdraws up to amount ETH. Reverts if amount > WITHDRAWAL_LIMIT (10 ETH) or insufficient balance.	pull(5 ether)
userBalance(address user)	external view	Returns the ETH balance of the specified user vault.	userBalance(0xAbC...)

## Deployed Contract Address

Sepolia

## Verified Contract Address:

0xBce61AFd3f89cb895f5262dd48fAa5A9C7C1bb31

## Explorer Link (e.g., Etherscan/Blockscout):

https://sepolia.etherscan.io/address/0xBce61AFd3f89cb895f5262dd48fAa5A9C7C1bb31#code

## Contract Code (Security Highlights)

  The code strictly follows the following security practices and standards:
  
  Reentrancy Protection: The noReentrancy modifier is applied to the pull function.
  
  CEI Pattern (Checks-Effects-Interactions): Strictly followed in the pull function, ensuring contract state updates occur before any external interaction.
  
  Safe Transfers: Uses call{value: amount}("") for withdrawals, with explicit error handling.
  
  Custom Errors: All require/revert statements use custom errors (e.g., BankCapReached, WithdrawalLimitExceeded, InsufficientBalance).

  NatSpec Documentation: All functions, state variables, and events are documented in English following Solidity conventions.

#### Portuguese

# KipuBank: Decentralized Ether Vault

O KipuBank é um contrato inteligente (Smart Contract) para a rede Ethereum que funciona como um cofre descentralizado (vault) para depósitos de ETH. Ele impõe limites de segurança tanto no nível de depósito individual (limite global) quanto no nível de saque (limite por transação), utilizando padrões de segurança de Solidity, como a proteção contra reentrância e o uso de erros personalizados.

## Funcionalidades

O KipuBank oferece as seguintes funcionalidades principais:

    Depósito de ETH: Usuários podem depositar ETH em cofres individuais (mapeados por endereço).

    Limite Global (Bank Cap): Imposto durante a implantação, limitando o ETH total que o contrato pode receber.

    Saque Limitado: Usuários podem sacar seu ETH, mas cada transação de saque é restrita a um limite imutável (WITHDRAWAL_LIMIT = 10 ETH).

    Contabilidade Transparente: Registra o saldo de cada usuário, o total de depósitos e a contagem de transações.

    Segurança Avançada: Implementa proteção contra reentrância e uma função de auditoria interna para verificar a integridade do saldo do contrato vs. a contabilidade interna.

## Instruções de Implantação

1. Clonar o Repositório

Bash

git clone https://github.com/FeLiPeOLi7/Web3-Blockchain.git
cd KipuBank

2. Configuração (Exemplo Hardhat/Foundry)

Defina suas chaves privadas e o URL da sua Testnet RPC em um arquivo .env.

3. Argumentos do Construtor

O contrato KipuBank requer um único argumento no momento da implantação:
Parâmetro	Tipo	Descrição	Exemplo
_bankCap	uint256	O limite máximo global de ETH que o contrato pode deter.	100 ether (100000000000000000000 wei)

### Como Interagir com o Contrato

Aqui estão as principais funções do KipuBank e como utilizá-las:

Funções para Usuários

Função	Visibilidade	Descrição	Exemplo de Uso
deposit()	external payable	Deposita ETH no cofre pessoal. Reverte se exceder o bankCap.	Chamar a função enviando X ETH.
pull(uint256 amount)	external	Saca até amount de ETH. Reverte se amount > WITHDRAWAL_LIMIT (10 ETH) ou saldo insuficiente.	pull(5 ether)
userBalance(address user)	external view	Retorna o saldo de ETH do user no cofre.	userBalance(0xAbC...)

Funções para o Owner

Função	Visibilidade	Modificador	Descrição
checkIntegrity()	external view	onlyOwner	Verifica se o saldo real de ETH do contrato corresponde à variável interna totalDeposits. Reverte se houver discrepância.

## Endereço do Contrato Implantado

Sepolia

Endereço do Contrato Verificado:

0xBce61AFd3f89cb895f5262dd48fAa5A9C7C1bb31

Link para o Explorer (Ex: Etherscan/Blockscout):

https://sepolia.etherscan.io/address/0xBce61AFd3f89cb895f5262dd48fAa5A9C7C1bb31#code

### Código do Contrato (Security Highlights)

O código segue rigorosamente as seguintes práticas de segurança e padrões:

    Proteção contra Reentrância: O modifier noReentrancy é aplicado à função pull.

    Padrão CEI (Checks-Effects-Interactions): Rigorosamente respeitado na função pull, garantindo que o estado do contrato seja atualizado antes de qualquer interação externa.

    Transferências Seguras: Uso do call{value: amount}("") para saques, com tratamento de erro explícito.

    Erros Personalizados: Todos os require/revert utilizam erros personalizados (ex: BankCapReached, WithdrawalLimitExceeded, InsufficientBalance).

    Documentação NatSpec: Todas as funções, variáveis de estado e eventos estão documentados em inglês, conforme as convenções de Solidity.
