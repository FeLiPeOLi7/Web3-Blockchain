// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

error NotBuyer();
error NotSeller();
error NotArbiter();
error NotAllowed();
error ZeroAmount();
error WithDrawFailed();
error WrongValue();
error InvalidState();


contract SimpleEscrow {
    address public immutable BUYER;
    address public immutable SELLER;
    address public immutable ARBITER;
    uint256 public immutable PRICE;

    event Deposited(address indexed from, uint256 value);
    event WithDraw(address indexed who, uint256 value);
    event Released(address indexed to, uint256 value);
    event Refunded(address indexed to, uint256 value);


    enum State{
        Deposited,
        Released,
        Refunded
    }

    State public state;

    
    mapping(address => uint256) public pullPayements;

    modifier onlyBuyer(){
        if(msg.sender != BUYER) revert NotBuyer();
        _;
    }

    // modifier onlySender(){
    //     if(msg.sender != SELLER) revert NotSeller();
    //     _;s
    // }

    modifier onlyArbiter(){
        if(msg.sender != ARBITER) revert NotArbiter();
        _;
    }

    modifier inState(State expected) {
        if (state != expected) revert InvalidState();
        _;
    }

    constructor(address _BUYER, address _SELLER, address _ARBITER, uint256 _PRICE){
        BUYER = _BUYER;
        SELLER = _SELLER;
        ARBITER = _ARBITER;
        PRICE = _PRICE;
    }

    // Função de depósito
    function deposit() external payable {
        if (msg.value != PRICE) revert WrongValue();

        state = State.Deposited;
        //pullPayements[msg.sender] += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    //  Usuário autorizado "puxa" seu próprio valor (Pull over Push)
    //  Protegido contra reentrância com noReentrancy modifier
    function withDraw() external{
        uint256 amount = pullPayements[msg.sender];
        if (amount == 0) revert NotAllowed();
        
        pullPayements[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        if(!success) revert WithDrawFailed();

        emit WithDraw(msg.sender, amount);
    }

    // Função para liberar pagamento ao vendedor
    function approveRelease() external onlyArbiter inState(State.Deposited) {
        state = State.Released;
        (bool success, ) = SELLER.call{value: PRICE}("");
        if (!success) revert WithDrawFailed();

        emit Released(SELLER, PRICE);
    }

    // Função para reembolsar o comprador em caso de disputa
    function refundBuyer() external onlyArbiter inState(State.Deposited) {
        state = State.Refunded;
        (bool success, ) = BUYER.call{value: PRICE}("");
        if (!success) revert WithDrawFailed();

        emit Refunded(BUYER, PRICE);
    }

    // Função para o comprador ou vendedor retirar seus fundos
    function withdraw() external {
        uint256 amount = pullPayements[msg.sender];
        if (amount == 0) revert NotAllowed();

        pullPayements[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert WithDrawFailed();

        emit WithDraw(msg.sender, amount);
    }

    // Função para obter o status atual da transação
    function status() external view returns (State) {
        return state;
    }

}
