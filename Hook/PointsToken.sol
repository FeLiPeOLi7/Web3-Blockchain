// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PointsToken is ERC20, Ownable {
    constructor(address _owner)
        ERC20("PointsToken", "POINTS")
        Ownable(_owner)
    {
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}