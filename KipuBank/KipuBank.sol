// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Erros personalizados: barateiam gas e padronizam mensagens
error NotOwner();
error ZeroAmount();
error NotAllowed();
error InsufficientBalance();
error ReentrancyDetected();
error BankCapReached();
error WithDrawalLimitExceed(uint256 limit, uint256 attemptedAmount);
error BalanceMismatch(); 

contract KipuBank {
    // owner: imutável após o deploy
    address public immutable owner;

    uint256 public immutable WITHDRAWAL_LIMIT = 10 ether;

    // Guarda os saldos
    mapping(address => uint256) public balances;

    // Proteção contra reentrância
    bool private locked;

    uint256 public bankCap;
    uint256 public totalDeposits;
    uint256 public totalWithDrawal;
    uint256 public depositsCount;
    uint256 public withdrawCount;

    // Eventos: facilitam auditoria e UX das dApps
    event Deposited(address indexed from, uint256 amount);
    event Pulled(address indexed who, uint256 amount);
    event FallbackCalled(address indexed from, uint256 value, bytes data);

    // Modifier: pré-condição reutilizável
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier noReentrancy() {
        if (locked) revert ReentrancyDetected();
        locked = true;
        _;
        locked = false;
    }

    constructor(uint256 _bankCap) {
        owner = msg.sender;
        bankCap = _bankCap;
        depositsCount = 0;
        withdrawCount = 0;
    }

    receive() external payable {
        if (msg.value == 0) revert ZeroAmount();
        emit Deposited(msg.sender, msg.value);
    }

    fallback() external payable {
        emit FallbackCalled(msg.sender, msg.value, msg.data);
    }

    // Função de depósito explícita (também aceita ETH)
	/*
	* @notice Deposits ETH into the contract, increasing the user's balance.
	* @dev Reverts if:
	* - No ETH is sent (`msg.value == 0`).
	* - The deposit would exceed the bank's capacity (`totalDeposits + msg.value > bankCap`).
	* Updates the user's balance, total deposits, and deposit count.
	* @return None (emits a `Deposited` event on success).
	*/
    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();

        if(totalDeposits + msg.value > bankCap) revert BankCapReached();

        totalDeposits += msg.value;
        balances[msg.sender] += msg.value;
        depositsCount++;

        emit Deposited(msg.sender, msg.value);
    }

    //  Usuário autorizado "puxa" seu próprio valor (Pull over Push)
    //  Protegido contra reentrância com noReentrancy modifier
	/*
	* @notice Withdraws ETH from the contract ("pull" pattern) to the caller's address.
	* @dev Requirements:
	* - Caller must have sufficient balance (`balances[msg.sender] >= amount`).
	* - `amount` must be > 0 and <= `WITHDRAWAL_LIMIT` (10 ETH).
	* - Reverts on reentrancy attempts (protected by `noReentrancy` modifier).
	* - Uses low-level `call` for ETH transfer and reverts on failure.
	* - Emits {Pulled} event on success.
	* @param amount The amount of ETH to withdraw (in wei).
	*/
    function pull(uint256 amount) external noReentrancy {
        if (amount == 0) revert NotAllowed();
	    if (amount > WITHDRAWAL_LIMIT) revert WithDrawalLimitExceed(WITHDRAWAL_LIMIT, amount);
        // Verificar se o contrato tem saldo suficiente
        if (balances[msg.sender] < amount) revert InsufficientBalance();

        balances[msg.sender] -= amount;
        totalWithDrawal += amount;
        withdrawCount++;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok){
            // Se a transferência falhar, reverter os 'effects' para restaurar o estado
            balances[msg.sender] += amount;
            withdrawCount--; 
            totalWithDrawal -= amount;
            revert NotAllowed();
        }

        emit Pulled(msg.sender, amount);
    }

    //  Função de leitura (view): não altera estado
    function contractBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    // Função Private: Verifica o saldo ETH real do contrato
    /**
     * @dev Fetches the actual ETH balance of the contract address on the blockchain.
     * This is a private internal check, usually for auditing or safety assertions.
     * @return The contract's current ETH balance (in wei).
     */
    function _getContractBalance() private view returns (uint256) {
        // 'address(this)' refere-se ao próprio contrato.
        // '.balance' é uma propriedade da EVM que retorna o saldo de ETH.
        return address(this).balance;
    }

	/*
	* @notice Verifies the integrity of the contract's accounting by comparing the recorded total deposits with the actual ETH balance.
	* @dev This function is restricted to the contract owner (`onlyOwner` modifier).
	* It ensures that the sum of all user balances (`totalDeposits`) matches the contract's actual ETH balance (`address(this).balance`).
	* If a mismatch is detected (e.g., due to unrecorded deposits/withdrawals or arithmetic errors), it reverts with `BalanceMismatch`.
	* Use this for auditing or sanity checks to detect inconsistencies early.
	* @return None (reverts on integrity failure, otherwise executes silently).
	*/
    function checkIntegrity() external view onlyOwner {
        uint256 realBalance = _getContractBalance();
        
        // Asserção: O saldo real do contrato deve ser igual ao que registramos
        if (realBalance != totalDeposits - totalWithDrawal) {
            // Se houver uma discrepância (ex: um depósito sem atualizar totalDeposits), revertemos.
            revert BalanceMismatch(); 
        }
    }
}