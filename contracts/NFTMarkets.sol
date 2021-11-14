// SPDX-License-Identifier: Unlicensed
//GameOperator
//1 Mint NFT 
/**
    1/ click buy BOX via ETH. Nhan dc n NFT. =>done.
    2/ Buy / Sell NFT.
*/
pragma solidity ^0.8.0; 
import "./TheBonyBastards.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract NNFMarkets is Ownable , ReentrancyGuard{  
  
    using SafeMath for uint256;
  
    uint256 public TRADE_FEE = 3;     
    uint256 public TRADE_FUNDED_FEE = 0; 
    TheBonyBastards nft; 
    IERC20 tokenUnity;
    address payable public walletFund;
    bool private openMartket = true;
    //
    mapping (uint256 => uint256) public listings; // id to price 
    mapping(uint => mapping(address => uint)) public nftsWithOffers;
    //Events Listen
    event TradeExecuted(address seller, address buyer, uint256 indexed tokenId, uint256 value);
    event List(uint256 indexed tokenId, uint256 value);
    event Delist(uint256 indexed tokenId);
    event NftOffered(uint256 indexed tokenId, address buyer, uint256 offerValue);
    event NftOfferCanceled(uint256 indexed tokenId, address sender);
    
    constructor(TheBonyBastards _bony ) {
        
        // tokenUnity = _tokenAddress;
        nft  = _bony;
    } 
 
    modifier onlyOwnerOf(uint _charId) {
        require(nft.ownerOf(_charId) == msg.sender , "This can only be called by the NFT owner!" ); 
        _;
    }
    //Modifier to enable/disable marketplace functions
    modifier marketIsOpen {
        require(openMartket, "Marketplace is disabled");
        _;
    }
 
    //Pharser 0: operator sale NFT, withdraw fund. token.
    function updateServiceFee(uint256 amount) external onlyOwner{
		TRADE_FEE = amount;
    } 
    function updateWalletFund(address payable _wallet) external onlyOwner{
		walletFund = _wallet;
    } 
    // change fundAddress. 
    function withdrawFund(uint256 amount) external onlyOwner{
          //require(msg.sender == owner, "This can only be called by the contract owner!");
        require(amount <= getBalance());
        walletFund.transfer(amount);  
    }
    function withdrawToken(uint256 _amount, address _toAddr) external onlyOwner{ 

        require(tokenUnity.balanceOf(msg.sender) >= _amount, "Market: insufficient token balance");
        tokenUnity.transferFrom(msg.sender, _toAddr , _amount);

    } 
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
    function getBalanceToken() public view returns (uint256) {
        //return address(this).balance;
        return tokenUnity.balanceOf(address(this));
    } 
   
    function toggleMarketPlace() external onlyOwner {
        openMartket = !openMartket;
    }
    
    //Credit to Ether Phrocks for marketplace functions https://etherscan.io/address/0x23fc142a6ba57a37855d9d52702fda2ec4b4fd53
    function listNft(uint256 tokenId, uint256 price) public onlyOwnerOf(tokenId) {
        //require(msg.sender == ownerOf(tokenId), "Must own Heroes to sell");
        require(openMartket, "Market is closed.");
        require(price > 0);
        listings[tokenId] = price;
        emit List(tokenId, price);
    }

    function delistNft(uint256 tokenId) public onlyOwnerOf(tokenId) {
        listings[tokenId] = 0;
        emit Delist(tokenId);
    }

    function buyNft(uint256 tokenId) public payable nonReentrant marketIsOpen {
        
        uint price = listings[tokenId];
        address seller = nft.ownerOf(tokenId);
        address buyer = msg.sender;

        require(price > 0, "NFT: not on sale");
        require(msg.value == price, "NFT: incorrect value");
        require(buyer != seller, "NFT: cannot buy your own NFT");
        
        //charge fee 
        uint tradeMarketFee = price.mul(TRADE_FEE).div(10**2);
        TRADE_FUNDED_FEE = TRADE_FUNDED_FEE.add( tradeMarketFee );
        //tradeMarketFee 
        listings[tokenId] = 0;
        nft.transferFrom(seller, buyer, tokenId);
        ////////
        
        uint tradeGetBalance  = price.sub(tradeMarketFee);
        
        (bool success, ) = seller.call{value: tradeGetBalance}("");
        
        require(success);
        
        emit Delist(tokenId);
        emit TradeExecuted(seller, msg.sender, tokenId, msg.value );
    }
    
   
}


 