// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* -------------------------------------------------------
                        IMPORTS
   ------------------------------------------------------- */

// Universal Router
import "https://raw.githubusercontent.com/Uniswap/universal-router/main/contracts/interfaces/IUniversalRouter.sol";
//import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol"; Nao funcionou

// Uniswap V4 Core Types
import "https://github.com/Uniswap/v4-core/blob/main/src/types/PoolKey.sol";
//import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol"; Nao funcionou
import "https://github.com/Uniswap/v4-core/blob/main/src/types/Currency.sol";
//import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import "https://raw.githubusercontent.com/Uniswap/universal-router/050b93cf4e9508b78412f23ad66e85d5c76a45b5/contracts/libraries/Commands.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Erros personalizados: barateiam gas e padronizam mensagens
error NotOwner();
error ZeroAmount();
error NotAllowed();
error InsufficientBalance();
error ReentrancyDetected();
error BankCapReached();
error WithDrawalLimitExceed(uint256 limit, uint256 attemptedAmount);
error BalanceMismatch(); 
error SwapFailed(bytes reason);

contract KipuBankV3 is ERC721, Ownable(msg.sender), ReentrancyGuard{
    uint256 public immutable WITHDRAWAL_LIMIT = 10 ether;

    uint256 public priceToken;
    uint256 public priceInETH;
    uint256 public priceInBTC;
    IERC20 paymentToken;
    uint256 public maxSupply;
    uint256 public tokenCurrentSupply_;
    bool public saleActive;
    
    AggregatorV3Interface public btcEthPriceFeed;
    AggregatorV3Interface public ethUsdPriceFeed;

    mapping(uint256 => bool) public isMinted;

    IUniversalRouter public immutable router;
    address public immutable USDC;

    event NFTMinted(address indexed to, uint256 tokenId);
    event MintedWithToken(address indexed to, uint256 tokenId, uint256 priceInToken);
    event MintedWithETH(address indexed to, uint256 tokenId, uint256 priceInETH);
    event MintedWithBTC(address indexed to, uint256 tokenId, uint256 priceInETH); // BTC price converted to ETH
    event PriceUpdated(uint256 newTokenPrice, uint256 newETHprice, uint256 newBTCprice);

    // Mapeamento de saldos para múltiplos tokens
    mapping(address => mapping(address => uint256)) public balances;

    uint256 public totalDeposits;
    uint256 public totalWithDrawal;
    uint256 public depositsCount;
    uint256 public withdrawCount;

    uint256 public immutable bankCapInUsd;        // ex: 1_000_000 * 1e8 → $1M
    uint256 public totalDepositsInUsd;

    // Eventos: facilitam auditoria e UX das dApps
    event Deposited(address indexed from, uint256 amount);
    event DepositedToken(address indexed user, address indexed token, uint256 amount, uint256 amountInUsd);
    event Pulled(address indexed who, uint256 amount);
    event FallbackCalled(address indexed from, uint256 value, bytes data);

    constructor(uint256 _bankCapInUsd,
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        address initialOwner,
        uint256 priceToken_,
        uint256 priceInETH_,
        uint256 priceInBTC_, 
        address paymentToken_,
        address _ethUsdPriceFeed,
        address _btcEthPriceFeed,
        address _router,
        address _usdc
    )
        ERC721(name_, symbol_)
    {
        paymentToken = IERC20(paymentToken_);
        maxSupply = maxSupply_;
        _transferOwnership(initialOwner);
        bankCapInUsd = _bankCapInUsd;
        priceToken = priceToken_;
        priceInETH = priceInETH_;
        priceInBTC = priceInBTC_;
        depositsCount = 0;
        withdrawCount = 0;

        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed); // Inicializa o oráculo
        btcEthPriceFeed = AggregatorV3Interface(_btcEthPriceFeed);

        require(_router != address(0), "Invalid router");
        router = IUniversalRouter(_router);
        USDC = _usdc;
    }

    receive() external payable {
        if (msg.value == 0) revert ZeroAmount();
        emit Deposited(msg.sender, msg.value);
    }

    fallback() external payable {
        emit FallbackCalled(msg.sender, msg.value, msg.data);
    }

	/**
	* @notice Converts a value between different decimal precisions (e.g., 6 → 18 decimals for USDC → ETH).
	* @dev Useful for token conversions where decimals differ (e.g., USDC uses 6 decimals, ETH uses 18).
	* If `fromDecimals == toDecimals`, returns the original value unchanged.
	* **Warning**: May revert on overflow if the conversion increases precision significantly.
	* 
	* @param value         The amount to convert (scaled to `fromDecimals`).
	* @param fromDecimals  The original decimal precision of `value` (e.g., 6 for USDC).
	* @param toDecimals    The target decimal precision (e.g., 18 for ETH).
	* @return The converted value, scaled to `toDecimals`.
	*/
    function convertToDecimals(uint256 value, uint8 fromDecimals, uint8 toDecimals) public pure returns (uint256) {
        if (fromDecimals > toDecimals) {
            return value / (10 ** (fromDecimals - toDecimals));
        } else if (fromDecimals < toDecimals) {
            return value * (10 ** (toDecimals - fromDecimals));
        }
        return value;
    }

	/**
	* @notice Converts a token amount to its equivalent value in USD.
	* @dev Supports ETH (native) and ERC20 tokens (e.g., USDC) with dynamic decimal handling.
	* For ETH, uses the Chainlink ETH/USD price feed. For ERC20 tokens like USDC,
	* assumes a 1:1 peg (1 token = 1 USD) after adjusting for decimals.
	* Reverts if the token does not support the `IERC20Metadata` interface (e.g., lacks `decimals()`).
	* 
	* @param token  The address of the token to convert (use `address(0)` for ETH).
	* @param amount The amount of the token to convert (in token's native decimals).
	* @return The equivalent value in USD, scaled to 18 decimals (e.g., `1e18` = 1 USD).
	*/
    function _toUsd(address token, uint256 amount) internal view returns (uint256) {
        if (token == address(0)) {
            // ETH → USD
            int256 ethPrice = getEthPriceInUsd(); // 8 decimals
            return (amount * uint256(ethPrice)) / 1e18;
        }else{
            //Works for USDC
            uint8 decimals = IERC20Metadata(token).decimals();
            uint256 amountIn18 = convertToDecimals(amount, decimals, 18);
            return amountIn18; // 1 USDC = 1 USD (1e18 scale)
        }
    }

    //Nossa _swapExactInputSingle
    /**
     * @notice Swaps an exact amount of an arbitrary token for USDC using the Universal Router.
     * @dev Uses a V3_SWAP_EXACT_IN command. Requires this contract to have pre-approved
     * the Universal Router to spend the tokenIn amount.
     * @param tokenIn The address of the token to be swapped (input).
     * @param amountIn The exact amount of `tokenIn` to be swapped.
     * @param fee The V3 pool fee (e.g., 500 for 0.05%).
     * @return amountOut The amount of USDC received (in USDC native decimals, typically 6).
     */
    function _swapArbitraryTokenToUSDC(
        address tokenIn,
        uint256 amountIn,
        uint24 fee
    ) internal returns (uint256 amountOut) {
        // Requisito 1: O KipuBankV3 deve transferir o tokenIn para o Router.
        // Já transferimos o tokenIn do usuário para o KipuBankV3 no `deposit()`.
        
        // Requisito 2: O KipuBankV3 deve ter pré-aprovado o Universal Router
        // para gastar o tokenIn. *Para este exercício, assumimos que a aprovação
        // máxima (type(uint256).max) foi feita uma vez pelo owner para o Router.*

        // 1. Codificar o Comando de Swap V3: TokenIn -> USDC
        // minAmountOut é definido como 1 para evitar ataques MEV neste exemplo simples, 
        // mas na produção usaria uma tolerância.
        // Encode the swap command
        bytes memory command = abi.encode(
            tokenIn,          // Token to swap
            USDC,             // Token to receive
            fee,              // Pool fee
            address(this),    // Recipient (this contract)
            amountIn,         // Exact input amount
            1                 // Minimum output (1 USDC to avoid MEV)
        );

        bytes memory commands = abi.encodePacked(
            Commands.V3_SWAP_EXACT_IN,  // Command type (uint8)
            command                      // Encoded command data
        );
        
        // 2. Armazenar o saldo inicial de USDC para medir o retorno
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(address(this));

        // 3. Executar o Swap
        try router.execute(commands, new bytes[](0), block.timestamp + 300) {
            // A execução foi bem-sucedida
        } catch Error(string memory reason) {
            revert SwapFailed(bytes(reason));
        } catch (bytes memory reason) {
            revert SwapFailed(reason);
        }

        // 4. Calcular o USDC recebido
        uint256 usdcBalanceAfter = IERC20(USDC).balanceOf(address(this));
        amountOut = usdcBalanceAfter - usdcBalanceBefore;

        if (amountOut == 0) revert("Swap resulted in zero USDC");
    }

	/**
    * @notice Deposits ETH, USDC, or any supported ERC20 token, converting non-USDC tokens to USDC.
    * @dev Arbitrary ERC20 tokens are swapped to USDC via the Universal Router.
    * The final amount stored in the user's balance is always the USDC equivalent.
    * The Bank Cap is checked against the final USDC value (scaled to 1e18).
    * * @param token The address of the token to deposit (address(0) for ETH).
    * @param amount The amount of tokens to deposit (ignored for ETH; use msg.value instead).
    */
    function depositArbitraryToken(address token, uint256 amount) external payable nonReentrant {
        uint256 finalAmount;
        address finalToken = USDC; // Saldo será sempre creditado em USDC

        if (token == address(0)) {
            // Caso 1: Depósito de ETH (Requisito: Usar o oráculo para calcular o valor em USD)
            if (msg.value == 0) revert ZeroAmount();
            amount = msg.value;

            // Mantendo a lógica do V2 para simplificar o manejo de ETH vs WETH/Router:
            // ETH depositado é convertido para USD via oráculo para fins de Cap.
            // NOTA: Para um sistema real, o ETH seria swappado para USDC via WETH usando o Router.
            // Para cumprir o requisito do V2, mantemos o oráculo.
            finalAmount = _toUsd(token, amount); // Valor em USD, escala 1e18
            finalToken = address(0); // Mantemos o token ETH no saldo, mas o valor é em USD (1e18)

        } else if (token == USDC) {
            // Caso 2: Depósito de USDC (sem swap)
            if (msg.value != 0) revert NotAllowed();
            if (amount == 0) revert ZeroAmount();

            // 1. Transferir USDC do usuário para o KipuBankV3
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
            if (!success) revert("Transfer failed");

            finalAmount = amount; // Armazena o USDC na sua decimal nativa (geralmente 6)
            finalToken = USDC;

        } else {
            // Caso 3: Depósito de Token Arbitrário (SWAP para USDC)
            if (msg.value != 0) revert NotAllowed();
            if (amount == 0) revert ZeroAmount();

            // 1. Transferir o Token Arbitrário para este Contrato
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
            if (!success) revert("Transfer failed");

            // 2. Executar o Swap (Token Arbitrário -> USDC)
            // Usamos uma taxa de 3000 (0.3%) como um padrão comum V3/V4
            uint256 usdcReceived = _swapArbitraryTokenToUSDC(token, amount, 3000);

            finalAmount = usdcReceived; // O USDC recebido (em 1e6)
            finalToken = USDC;
        }

        // CÁLCULO FINAL E VERIFICAÇÃO DO BANK CAP
        uint256 amountInUsd;
        uint8 decimals = 18; // Padrão para ETH (via oráculo)

        if (finalToken == USDC) {
            // Se for USDC (caso 2 ou 3), pegamos as decimais do USDC (geralmente 6)
            // e convertemos o valor recebido para 1e18 para checar o Cap.
            decimals = IERC20Metadata(USDC).decimals();
            amountInUsd = convertToDecimals(finalAmount, decimals, 18);
        } else if (finalToken == address(0)) {
            // Se for ETH (caso 1), _toUsd já retorna em USD, escala 1e18.
            amountInUsd = finalAmount;
        }

        // 3. Aplicar o limite do banco (Bank Cap)
        if (totalDepositsInUsd + amountInUsd > bankCapInUsd) revert BankCapReached();

        // 4. Atualizar saldos (Sempre em USDC, exceto ETH que usa o oráculo)
        balances[msg.sender][finalToken] += finalAmount;
        totalDepositsInUsd += amountInUsd;
        depositsCount++;

        emit DepositedToken(msg.sender, finalToken, finalAmount, amountInUsd);
    }


    // Função de saque
	/**
	* @notice Withdraws a specified amount of tokens (ETH or ERC20) from the user's balance in the contract.
	* @dev This function enforces a withdrawal limit (`WITHDRAWAL_LIMIT`) per transaction to mitigate
	* large outflows. For ETH withdrawals, it updates the `totalDepositsInUsd` accounting.
	* Reentrancy protection is applied via the `nonReentrant` modifier.
	* 
	* Requirements:
	* - `amount` must be greater than 0.
	* - `amount` must not exceed `WITHDRAWAL_LIMIT`.
	* - User must have sufficient balance (`balances[msg.sender][token] >= amount`).
	* 
	* Emits: {Pulled} event upon successful withdrawal.
	* 
	* @param token The address of the token to withdraw (use `address(0)` for ETH).
	* @param amount The amount of tokens to withdraw (in token's native decimals).
	*/
    function pull(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert NotAllowed();
        if (amount > WITHDRAWAL_LIMIT) revert WithDrawalLimitExceed(WITHDRAWAL_LIMIT, amount);

        uint256 userBalance = balances[msg.sender][token];
        if (userBalance < amount) revert InsufficientBalance();

        balances[msg.sender][token] -= amount;
        totalWithDrawal += amount;
        withdrawCount++;

        uint256 amountInUsd = 0;
        if (token == address(0)){
            amountInUsd = _toUsd(token, amount); // converte ETH em USD
            totalDepositsInUsd -= amountInUsd;
        }

        if (token == address(0)) {
            // Saque em ETH
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            // Saque em ERC-20
            IERC20 tokenContract = IERC20(token);
            require(tokenContract.transfer(msg.sender, amount), "Token transfer failed");
        }

        emit Pulled(msg.sender, amount);
    }

    //  Função de leitura (view): não altera estado
	/**
	* @notice Returns the recorded balance of a specific token for a given user in the contract.
	* @dev This function retrieves the internal accounting balance (not the actual on-chain token balance)
	* for a user's deposits. For ETH, use `address(0)` as the token parameter.
	* @param user The address of the user whose balance is being queried.
	* @param token The address of the token to check (use `address(0)` for ETH).
	* @return The recorded balance of the specified token for the user (in token's native decimals).
	*/
    function contractBalance(address user, address token) external view returns (uint256) {
        return balances[user][token];
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


    /// @notice Returns the current supply of minted NFTs
    function currentSupply() external view returns (uint256) {
        return tokenCurrentSupply_;
    }

    /// @notice Set whether the sale is active or not
    function setSaleActive(bool active) external onlyOwner {
        saleActive = active;
    }

    /// @notice Update the prices for token, ETH, and BTC payments
    function setPrices(uint256 priceToken_, uint256 priceInETH_, uint256 priceInBTC_) external onlyOwner {
        priceToken = priceToken_;
        priceInETH = priceInETH_;
        priceInBTC = priceInBTC_;
        emit PriceUpdated(priceToken_, priceInETH_, priceInBTC_);
    }

    /// @notice Mint NFT paying with a token (ERC20)
    /// @param to Address to receive the NFT
    function mintWithToken(address to) external nonReentrant {
        if (!saleActive) revert("Sale not active");
        if (tokenCurrentSupply_ >= maxSupply) revert("Max supply reached");
        if (to == address(0)) revert("Zero address");

        // Transfer payment token from user to this contract
        bool success = paymentToken.transferFrom(msg.sender, address(this), priceToken);
        require(success, "NFTPayment: token transfer failed");

        uint256 tokenId = tokenCurrentSupply_;
        tokenCurrentSupply_++;

        _safeMint(to, tokenId);

        emit MintedWithToken(to, tokenId, priceToken);
    }

    /// @notice Mint NFT paying with ETH
    /// @param to Address to receive the NFT
    function mintWithETH(address to) external payable nonReentrant {
        if (!saleActive) revert("Sale not active");
        if (tokenCurrentSupply_ >= maxSupply) revert("Max supply reached");
        if (to == address(0)) revert("Zero address");
        if (msg.value < priceInETH) revert("Insufficient payment");

        uint256 tokenId = tokenCurrentSupply_;
        tokenCurrentSupply_++;

        _safeMint(to, tokenId);

        // Refund excess ETH if any
        if (msg.value > priceInETH) {
            (bool refundSuccess,) = payable(msg.sender).call{value: msg.value - priceInETH}("");
            require(refundSuccess, "NFTPayment: ETH refund failed");
        }

        emit MintedWithETH(to, tokenId, priceInETH);
    }

    /// @notice Mint NFT paying with BTC (converted to ETH)
    /// @param to Address to receive the NFT
    function mintWithBTC(address to) external payable nonReentrant {
        if (!saleActive) revert("Sale not active");
        if (tokenCurrentSupply_ >= maxSupply) revert("Max supply reached");
        if (to == address(0)) revert("Zero address");

        int256 btcEthPrice = getBTCEthPrice();
        if (btcEthPrice <= 0) revert("Insufficient payment");

        uint256 calculatedPriceInETH = (priceInBTC * uint256(btcEthPrice)) / 1e18;
        if (msg.value < calculatedPriceInETH) revert("Insufficient payment");

        uint256 tokenId = tokenCurrentSupply_;
        tokenCurrentSupply_++;

        _safeMint(to, tokenId);

        // Refund excess ETH if any
        if (msg.value > calculatedPriceInETH) {
            (bool refundSuccess,) = payable(msg.sender).call{value: msg.value - calculatedPriceInETH}("");
            require(refundSuccess, "NFTPayment: ETH refund failed");
        }

        emit MintedWithBTC(to, tokenId, calculatedPriceInETH);
    }

	/**
	* @notice Fetches the latest BTC/ETH price from the Chainlink oracle.
	* @dev Retrieves the most recent price feed data for BTC denominated in ETH (18 decimals).
	* Uses the `latestRoundData()` method from the Chainlink AggregatorV3Interface.
	* Returns the raw price value (scaled by 18 decimals) as reported by the oracle.
	* Callers should handle cases where the returned price is <= 0 (invalid/stale data).
	* @return answer The BTC/ETH price (scaled by 1e18) or a negative/zero value if invalid.
	*/
    function getBTCEthPrice() public view returns (int256) {
        // prettier-ignore
        (
            /* uint80 roundId */
            ,
            int256 answer,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = btcEthPriceFeed.latestRoundData();
        return answer;
    }

    function getEthPriceInUsd() public view returns (int256) {
    //Obtém o preço do ETH em USD do oráculo Chainlink
    (
        /* uint80 roundId */,
        int256 price,
        /* uint256 startedAt */,
        /* uint256 updatedAt */,
        /* uint80 answeredInRound */
    ) = ethUsdPriceFeed.latestRoundData();
    
        return price; // Retorna o preço de ETH em USD
    }
}