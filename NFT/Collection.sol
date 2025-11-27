// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract NFTdaUFES is ERC721, Ownable(msg.sender), ReentrancyGuard {
    uint256 public priceToken;
    uint256 public priceInETH;
    uint256 public priceInBTC;
    IERC20 paymentToken;
    uint256 public maxSupply;
    uint256 public tokenCurrentSupply_;
    bool public saleActive;
    
    AggregatorV3Interface public btcEthPriceFeed;

    mapping(uint256 => bool) public isMinted;

    event NFTMinted(address indexed to, uint256 tokenId);
    event MintedWithToken(address indexed to, uint256 tokenId, uint256 priceInToken);
    event MintedWithETH(address indexed to, uint256 tokenId, uint256 priceInETH);
    event MintedWithBTC(address indexed to, uint256 tokenId, uint256 priceInETH); // BTC price converted to ETH
    event PriceUpdated(uint256 newTokenPrice, uint256 newETHprice, uint256 newBTCprice);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        address initialOwner, 
        uint256 priceToken_,
        uint256 priceInETH_,
        uint256 priceInBTC_,
        address paymentToken_
    )
        ERC721(name_, symbol_)
    {
        maxSupply = maxSupply_;
        saleActive = false;
        priceToken = priceToken_;
        priceInETH = priceInETH_;
        priceInBTC = priceInBTC_;
        paymentToken = IERC20(paymentToken_);
        _transferOwnership(initialOwner);
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
}