// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract TimeLock{
    address public immutable OWNER;

    mapping (address => uint256) public balances;
    mapping (address => uint256) public unlockTimes;

    uint256 public blockTimestamp;
    uint256 public releaseTime;


    event Deposited(address indexed sender, uint256 amount);
    event LockExtension(address indexed sender, uint256 unlockTime);
    event Pulled(address indexed sender, uint256 amount);

    error ZeroAmount();
    error LockTooShort();
    error NotUnlocked();
    error NoBalance();
    error NotOwner();

    modifier onlyOwner(){
        if(msg.sender != OWNER) revert NotOwner();
        _;
    }

    constructor(uint256 _lockDuration){
        OWNER = msg.sender;
        if(_lockDuration < 1 days) revert LockTooShort();
        releaseTime = uint64(block.timestamp + _lockDuration);
    }

    function storeTimestamp() public {
        blockTimestamp = block.timestamp;
    }

    function getTimestamp() public view returns (uint256) {
        return blockTimestamp;
    }

    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function pull() external onlyOwner {
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert ZeroAmount();

        if (address(this).balance < amount) revert NoBalance();

        if(block.timestamp < releaseTime) revert NotUnlocked();

        balances[msg.sender] = 0;

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "transfer failed");

        emit Pulled(msg.sender, amount);
    }

}