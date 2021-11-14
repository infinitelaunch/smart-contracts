// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0; 
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';  
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TheBonyBastards is ERC721, ERC721Burnable, Ownable,
 ERC721Enumerable, ReentrancyGuard {
     
     using SafeMath for uint256;
     using Strings for uint256; 

    address private operator; 
    address payable walletFund;
    
    bool private isEnableTrade = true;
    string private _baseURIextended; 
    uint256 public constant bonePrice = 100000000000000000; //0.1 BNB
    uint public MAX_MINT = 10;
    uint public MAX_SUPPLY = 8888; 
    uint public REVEAL_TIMESTAMP ;
    bool public saleIsActive = false;
    uint256 public startingIndexBlock;
    uint256 public startingIndex;
    
    // Mapping from token ID to banstatus
    mapping(uint256 => bool) private _bans;
    mapping(address => bool) private _ownerbans;  

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;  
    mapping (uint256 => string) private _tokenURIs;

    constructor() ERC721("The Bony Bastards" , "TBB") {
		
		operator = msg.sender;
        REVEAL_TIMESTAMP = block.timestamp  + (86400 * 9);
        _baseURIextended = "https://api.infinitelaunch.io/nfts/";
    }
    
	modifier isOperator() {
		require(msg.sender == operator, "Service for marketer only");
		_;
	}   
    /**
    * Mints Bones
    */
    function mintBones(uint numberOfTokens) public payable {
        
        uint256 addrBalance = this.balanceOf(msg.sender);
        require(addrBalance + numberOfTokens <= MAX_MINT, "Can only mint 10 tokens per account");
        uint256 currentSupply = _tokenIds.current(); 
        require(saleIsActive, "Sale must be active to mint Bone");
        require(numberOfTokens <= MAX_MINT, "Can only mint 10 tokens at a time");
        require(currentSupply + numberOfTokens <= MAX_SUPPLY, "Purchase would exceed max supply of Bone");
        require(bonePrice.mul(numberOfTokens) == msg.value, "BNB value sent is not correct");
        
        for(uint i = 0; i < numberOfTokens; i++) {
            _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();
            if (newItemId < MAX_SUPPLY) {
                _safeMint(msg.sender, newItemId);
            }
        } 
        // If we haven't set the starting index and this is either 1) the last saleable token or 2) the first token to be sold after
        // the end of pre-sale, set the starting index block
        if (startingIndexBlock == 0 && (totalSupply() == MAX_SUPPLY || block.timestamp >= REVEAL_TIMESTAMP)) {
            startingIndexBlock = block.number;
        } 
    }
    
    // function minted() public onlyOwner{
        
    //     for(uint i = 0; i < 10; i++) {
    //         _tokenIds.increment();
    //          uint256 newItemId = _tokenIds.current();
    //         if (newItemId < MAX_SUPPLY) {
    //             _safeMint(msg.sender, newItemId); 
    //         }
    //     }
    //     if (startingIndexBlock == 0 && (totalSupply() == MAX_SUPPLY || block.timestamp >= REVEAL_TIMESTAMP)) {
    //         startingIndexBlock = block.number;
    //     }
    // }

    /**
     * Set the starting index for the collection
     */
    function setStartingIndex() public {
        require(startingIndex == 0, "Starting index is already set");
        require(startingIndexBlock != 0, "Starting index block must be set");
        startingIndex = uint(blockhash(startingIndexBlock)) % MAX_SUPPLY;
        // Just a sanity case in the worst case if this function is called late (EVM only stores last 256 block hashes)
        if (block.number.sub(startingIndexBlock) > 255) {
            startingIndex = uint(blockhash(block.number - 1)) % MAX_SUPPLY;
        }
        // Prevent default sequence
        if (startingIndex == 0) {
            startingIndex = startingIndex.add(1);
        }
    } 
    /**
     * Set the starting index block for the collection, essentially unblocking
     * setting starting index
     */
    function emergencySetStartingIndexBlock() public onlyOwner {
        require(startingIndex == 0, "Starting index is already set"); 
        startingIndexBlock = block.number;
    }  

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        override(ERC721, ERC721Enumerable)
    {
        require(!(_bans[tokenId] == true), "ERC721: This character is baned");
        require(!(_ownerbans[from] == true), "ERC721: This owner is baned");
        if(!isEnableTrade){
            if(from != address(0)){
                revert("ERC721: This owner not allow for trading");
            }
        } 

        super._beforeTokenTransfer(from, to, tokenId); 
    }
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
    Operation Method
     */
    function setRevealTimestamp(uint256 revealTimeStamp) public onlyOwner {
        REVEAL_TIMESTAMP = revealTimeStamp;
    }
    /*
    * Pause sale if active, make active if paused
    */
    function withdrawFund(uint256 amount) external onlyOwner{
        require(walletFund != address(0), "wallet is the zero address");
        //require(msg.sender == owner, "This can only be called by the contract owner!");
        require(amount <= getBalance());
        walletFund.transfer(amount);  
    }
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
    function flipSaleState() public onlyOwner {
        saleIsActive = !saleIsActive;
    }
     
	function updateOperator(address _operator) external onlyOwner{
		operator = _operator;
	}
	function updateWalletFund(address payable _walletFund) external onlyOwner{
		require(_walletFund != address(0), "_walletFund is the zero address");
        walletFund = _walletFund;
	}  
	function flipIsEnableTrade() public onlyOwner {
        isEnableTrade = !isEnableTrade;
    } 
	function updateBanOwnerStatus(address _owner, bool _status) external isOperator{
		_ownerbans[_owner] = _status;
	} 
	function updateBanStatus(uint256 _tokenId,bool status) external isOperator{
		_bans[_tokenId] = status;
	}
	 
    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIextended = baseURI_;
    } 
     
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }
        
}