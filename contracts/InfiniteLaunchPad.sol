//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Utility.sol";
/**
Seed sale: 10% unlock first time / Vesting 15% / 30 days.
PrivateSale : 10% unlock first time / Vesting 22,5% / 30 days.
Public sale: 100% unlock 
whitelist required all
enum RoundStages {
        START_WHITELIST, // init ido: can add whitelist, set cap, set time, vest rule.
        START_IDO,  // can only buy token.
        ADD_LIQUIDITY, // can only call withdraw to add liquidity.
        FINISHED,   // can widrawfund, start vest token.
        FAILED      // can only refund.
}
*/

contract InfiniteLaunchPadPool is Context, Ownable{

    using SafeMath for uint256;
    string public CROWDSALENAME;// "SEED ILA, PRIVATE SALE ABz.." 
    enum RoundStages {
        START_WHITELIST,
        START_IDO,
        FILLED,
        FINISHED,
        FAILED
    }
    RoundStages public stage = RoundStages.START_WHITELIST;
    
    IERC20 public immutable tokenUnity;  //fixed BUSD; 
    IERC20 public token;
    
    address payable public wallet;//fund raised will send back to here.
    //contributions users attr.
    mapping(address => uint256) public contributions;      // BUSD user deposit per account.
    mapping(address => uint256) public userTokenBalance;   // Total Balance of user when contribute.
    mapping(address => uint256) public userVestedBalance;  // Total Balance  vested of user when claims.
    mapping(address => uint256) public lastTimeVesting;    // last time clammed for linear vested
    uint256 public weiAmountRaised;   //total busd raised.
    uint256 public weiAmountTotalReleased;   //total busd raised.

    //=whitelist= admin operation address for whitelist and setCap.
    uint256 public ilaThreadHold = 0; //default true.
    address public adminCap;
    address public adminWhitelist;
    bool public whitelistRequired = true; //default true.
    mapping(address => bool) public whitelist; // individual cap, only adminWhitelist can update.
    mapping(address => uint256) public caps; // individual cap, only adminCap can update.

    //===TIMELOCK===
    //operation pause & time open
    bool public isPaused; 
    uint256 public openingTime;
    uint256 public closingTime;
    uint256 public timePass; // time unlock linear 
    uint256 public claimRate; // linear % unlock . 10% seed, 22.5% privatesale. 100% public sale. for each time claim
    uint256 public totalTimeLock;// total LockedTime 
    uint256 public firstTimeClaimRate = 100; // first time unlock value 10%
    
    //===CAP SETTINGS
    uint256 public HARDCAP; //Total Raised Goal
    uint256 public rate;    //Token Price 1BUSD = (rate)Token
    uint256 public individualMinCap = 1* 10**18; //1 BUSD
    uint256 public individualMaxCap; //300000000000000000000 300 BUSD 1000000000000000000000
    
    //====Liqudity and init price 
    bool public isAddedLiquidity = false; 
    uint256 public liqudityTokenAmount;  
    uint256 public liqudityBUSDRate; // 60% sale will add to init liquidity 
    uint256 public liqudityPriceInit; // init token price liquidity 
  
    //Events.
    event EventAddedBuyToken(address user, uint256 weiAmount); //Admin add and init contributed address.
    event EventBuyToken(address user, uint256 weiAmount);   //only buy make this event  
    event SetWhiteCap(address user, uint256 weiAmount);     
    event WhitelistedAdded(address indexed account);        
    event WhitelistedRemoved(address indexed account);
    event ReleaseAmount(address user, uint256 weiAmount);
    event MakeFailedRaised(string reason);
    event EventRefunds(address user, uint256 weiAmount);
    // this constructor for testmode.
     
    constructor(
        string memory _name,
        address payable _wallet,
        address _tokenSell,
        address _tokenBUSD
        )
        payable{
        require(_wallet != address(0), "Crowdsale: _wallet is the zero address");
      
        CROWDSALENAME = _name;
        wallet =  _wallet;
        token  =  IERC20(_tokenSell); 
        tokenUnity = IERC20(_tokenBUSD);  
        
        weiAmountRaised = 0;  // total raised.
        adminWhitelist = msg.sender;
        adminCap = msg.sender;
        whitelistRequired = true;  // always 
        isPaused =false; //init is not paused.
    }  
     
    /**
     * Operation 
    */
    modifier atRound(RoundStages _stage) {
        require(stage == _stage, "Not ready to call. pls check stage");
        _;
    }
    function setNextRound() public onlyOwner {
    	stage = RoundStages(uint(stage) + 1);
    } 
    //=========================OPERATOR=================================//
    function setUpdateRoudState( uint _stage) public onlyOwner {
        require( _stage <= 4, "Stage >=0 and <= 4" );
        stage = RoundStages(_stage);
    }
    function setWhitelistRequired(bool enabled) public onlyOwner {
    	whitelistRequired = enabled;
    }
    
    function setPaused(bool enabled) public onlyOwner {
    	isPaused = enabled;
    }
    function setIsAddedLiquidity(bool status) public onlyOwner {
    	// false -> not yet add liquidity . true : added.
        isAddedLiquidity = status;
    }  
    function setAdminWhitelist(address admin) public onlyOwner {
    	adminWhitelist = admin;
    }
    function setAdminCap(address admin) public onlyOwner {
    	adminCap = admin;
    }
    function setTokenSale(address _token) public onlyOwner returns(bool) {
    	token  =  IERC20(_token); 
        return true;
    } 
    function setTokenSale(uint256 _ilaThreadHold) public onlyOwner returns(bool){
    	ilaThreadHold  =  _ilaThreadHold; 
        return true;
    } 
    
    /*
    whitelist manager
    */
    function setWhitelistCap(address beneficiary, uint256 capAmount) public returns(bool){
        require( msg.sender == adminCap , "Cap only admin cap can change value.");
        
        caps[beneficiary] = capAmount;
        whitelist[beneficiary] = true;

        emit SetWhiteCap(beneficiary, capAmount);
        return true;
    }  
    
    function isWhitelisted(address account) public view returns (bool) {
        return whitelist[account];
    } 
    function addWhitelisted(address account) public returns(bool) {
        require ( msg.sender == adminWhitelist ,  "WhitelistAdminRole: caller does not have the WhitelistAdmin role" );
        whitelist[account] = true;
        return true;
    } 
    function removeWhitelisted(address account) public returns(bool) {
        require ( msg.sender == adminWhitelist ,  "WhitelistAdminRole: caller does not have the WhitelistAdmin role" );
        whitelist[account] = false;
        return true;
    } 
    function addWhitelisted(address[] memory accounts) public returns(bool) {
        
        require ( msg.sender == adminWhitelist ,  "WhitelistAdminRole: caller does not have the WhitelistAdmin role" );
        
        for (uint256 index = 0; index < accounts.length; index++) {
            //addWhitelisted(accounts[account]);
            whitelist[ accounts[index] ] = true;
        }
        return true;
    }   
    //==================================================//  
    function initPoolData( 
            uint256 _maxCap,
            uint256 _hardCap,
            uint256 _rate,  
            uint256 _openingTime,
            uint256 _closingTime,
            uint256 _timePass,
            uint256 _claimRate,
            uint256 _totalTimeLock,
            uint256 _firstTimeClaimRate ) public onlyOwner returns(bool){
             
            require( _maxCap > 0 , "_maxCap must > 0"); 
            require(_hardCap > _maxCap, "HardCap must > maxCap");
            require( _rate > 0 , "Rate must > 0");

            require( _timePass > 0 , "Rate _timePass > 0");
            require( _claimRate > 0 , "Rate _timePass > 0");
            require( _totalTimeLock > 0 , "Rate _totalTimeLock > 0");
            require( _firstTimeClaimRate > 0 , "Rate _firstTimeClaimRate > 0");

            require( block.timestamp < _openingTime, "OpeningTime must required is next time");
            require( _closingTime > _openingTime, "ClosingTime time must required is next time");  
             
            //token settings. 
            rate = _rate;
            HARDCAP =  _hardCap; //1000000* 10**18; //1m BUSD  ;        
            individualMaxCap =  _maxCap;  //500* 10**18;//Max cap 300 BUSD
            
            //time settings.
            openingTime = _openingTime;
            closingTime = _closingTime;
            totalTimeLock = _totalTimeLock;
            timePass = _timePass;

            //Vesting rate settings
            claimRate = _claimRate;
            firstTimeClaimRate = _firstTimeClaimRate; 

            return true;
    }
    function updatePoolTimeOpen(uint256 _openingTime, uint256 _closingTime,uint256 _timePass,uint256 _totalTimeLock ) public onlyOwner returns(bool){
            require( _closingTime > _openingTime, "ClosingTime time must required is next time");  
            openingTime = _openingTime;
            closingTime = _closingTime; 
            totalTimeLock = _totalTimeLock;
            timePass = _timePass;
            return true;
    }
    function updateTokenSale( address _tokenSell ) public onlyOwner returns(bool){
            
            token  =  IERC20(_tokenSell); 
            return true;
    }
    
    /**
    Get crowdsale infomations */
    function getPoolInfo() public view returns(
        uint256,uint256,uint256,uint256,uint256,uint256,uint256){
        return(
            HARDCAP, rate,
            openingTime, closingTime,
            individualMinCap , individualMaxCap, weiAmountRaised);
    }   
    function getCap(address beneficiary) public view returns (uint256) {
        uint256 capValue =  caps[beneficiary];
        if (capValue == 0) {
            capValue = individualMaxCap;
        }
        return capValue;
    }

    function getAccountInfo(address account) public view returns (uint256 , uint256 , uint256 , uint256  ){
        return (contributions[account], 
                userTokenBalance[account], 
                userVestedBalance[account],
                lastTimeVesting[account]  );
    }
    
    //==================================================//
    /**
     * buyToken  
     weiAmount input is BUSD wei
     retrun tokens.
     */
     /**
     * @dev Extend parent behavior requiring purchase to respect the beneficiary's funding cap.
     * @param beneficiary Token purchaser
     * @param weiAmount Amount of wei contributed
     */
    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view {
        
        require(beneficiary != address(0), "ILALaunchPad: beneficiary is the zero address");
        
        require(weiAmount != 0, "ILALaunchPad: weiAmount is 0");
      
        uint256 allowance = tokenUnity.allowance(beneficiary, address(this));
        
        require(allowance >= weiAmount, "ILALaunchPad: Check the token allowance"); 
        
        require(tokenUnity.balanceOf(beneficiary) >= weiAmount, "ILALaunchPad: insufficient token balance");
        
        require(contributions[beneficiary].add(weiAmount) <= getCap(beneficiary), "ILALaunchPad: beneficiary's cap exceeded");
        
        if (whitelistRequired) {
             require(isWhitelisted(beneficiary), "ILALaunchPad: beneficiary doesn't have the Whitelisted role");
        } 

    }  
    /**
    Final Buy token */
    function _getTokenAmount(uint256 weiAmount) internal view returns (uint256) {
        return weiAmount.mul(rate);
    }  
    
    function buyTokens(uint256 weiAmount) public atRound(RoundStages.START_IDO) returns (uint256){
        
        require(!isPaused, "ILALaunchPad: Crowdsale is paused.");
        require( block.timestamp >= openingTime, "ILALaunchPad: Sale is not yet open.");
        require( block.timestamp < closingTime, "ILALaunchPad: Sale is closed.");
        require( weiAmountRaised.add(weiAmount) <= HARDCAP, "ILALaunchPad: Total amount is over goal.");
        //Get weiAmount 
        _preValidatePurchase(msg.sender, weiAmount);
        
        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(weiAmount);
        //tranfer raised funded amount 
        tokenUnity.transferFrom(msg.sender, address(this) , weiAmount);

        weiAmountRaised = weiAmountRaised.add(weiAmount);
        contributions[msg.sender] = contributions[msg.sender].add(weiAmount);
        userTokenBalance[msg.sender] = userTokenBalance[msg.sender].add(tokens);
        
        emit EventBuyToken(msg.sender, weiAmount);
        
        if (weiAmountRaised >= HARDCAP){
            stage = RoundStages.FILLED;
        }

        return tokens;
    } 

    /**
    * @dev Calculates the amount that has already vested.
    */
    function getReleasedAmount(address account) public view returns(uint256) {
        return userVestedBalance[account];
    }
    
    /**
        *vest :
        total : 100
        require vested <= total
        first time vested firstClaimRate%
        next Vesting is claimRate
        if totalLockTime = 0 => vested all.
        if firstTimeVested = 100 => vested all.
     */
    function release() public returns (bool){
        return linearRelease(msg.sender);
    }
    function releaseForAddress(address _account ) public onlyOwner returns (bool){
        return linearRelease(_account);
    }
    function linearRelease(address _account ) internal atRound(RoundStages.FINISHED) returns (bool){
        
        require( !isPaused  , "ILALaunchPad: This contract is paused");
        
        require( block.timestamp > closingTime  , "ILALaunchPad: This time claim is not valid");
        
        require( contributions[_account] > 0 , "ILALaunchPad: This address not valid");
        
        require( userVestedBalance[_account] < userTokenBalance[_account], "ILALaunchPad: Your account has vested all");
            
        // this time can vest amount
        uint256 releaseAmount = 0 ;
        //always allow first time claim.
        if( totalTimeLock >0 && lastTimeVesting[_account] == 0){
            releaseAmount = userTokenBalance[_account].mul(firstTimeClaimRate).div(10**3);// ammount = total * (claimRate)
        }else{
            //each time vest claimRate % totalBought
            require( block.timestamp - lastTimeVesting[_account] > timePass , "ILALaunchPad: Invalid time vestting. Waiting for next vesting time.");
            releaseAmount = userTokenBalance[_account].mul(claimRate).div(10**3);// ammount = total * (claimRate)
        }
        
        if (block.timestamp >= closingTime.add(totalTimeLock) ) {
            // user can vest all at one time. if publicSale totalTimeLock = 0 =>> allow vest all first time
            releaseAmount = userTokenBalance[_account] - userVestedBalance[_account]; // return everything if vesting period ended
        }
        
        require( userVestedBalance[_account].add(releaseAmount) <= userTokenBalance[_account], "ILALaunchPad: invalid amount vested ");
        
        lastTimeVesting[_account] = block.timestamp;
        userVestedBalance[_account] = userVestedBalance[_account].add(releaseAmount);
        token.transfer( _account, releaseAmount);
        
        weiAmountTotalReleased = weiAmountTotalReleased.add(releaseAmount);
        
        emit ReleaseAmount(_account, releaseAmount);  
        return true;
    }

    /**
    Finish stage:
        - Add liqudity if Liquidity reqired 
        liquidity Rate.
        slip Amount Token, Add to liquidity.
        tranfer Funded to _liqudity
        tranfer Token to _liqudity
        
        - withdraw fund
        to complate ?
             1. if private sale => admin call tranferFund. 
             2. if PublicSale => Call Add liqudity before withdraw fund. 

     */
     
    function withdrawFund(address toWallet) public onlyOwner returns(bool){ 
        require(tokenUnity.balanceOf( address(this) ) >0 , "Raised balance =0 ");
        tokenUnity.transfer(toWallet , weiAmountRaised  );

        return true;
    }
    function withdrawToken(address toWallet , uint256 amount) public onlyOwner  returns(bool){ 
        
        require(token.balanceOf( address(this) ) >0 , "Raised balance =0 ");
        token.transfer(toWallet , amount  ); 
        return true; 
    }
    function withdrawNativeToken(uint256 amount) public onlyOwner  returns(bool){ 
       
        uint256 nativeTokenBalance = address(this).balance;
        require( amount <= nativeTokenBalance,  "Native: insufficient token balance" );
        wallet.transfer(amount);   
        return true; 
    }   

    //============ Operator refund. Canceled or MakeFailed ============//
    function setMakeFailedOrCanceled(string memory _reason ) public onlyOwner {   
        stage = RoundStages.FAILED;
        isPaused = true;
        emit MakeFailedRaised(_reason);
    } 
    /** refund
      - call only when MAKE FAILED
      - refund only whois call buyTokens.
      - if address added by admin  -> cant not get refund here.
    */
    function refunds() public atRound(RoundStages.FAILED) returns (uint256){
        
        require(contributions[msg.sender] > 0 , "Contribution must > 0");
        //Get weiAmount
        uint256 weiAmount = contributions[msg.sender];
        //tranfer raised funded amount 
        weiAmountRaised = weiAmountRaised.sub(weiAmount);
        contributions[msg.sender] = 0;
        userTokenBalance[msg.sender] = 0;
        tokenUnity.transfer(msg.sender, weiAmount);
        emit EventRefunds(msg.sender, weiAmount);
        return weiAmount;
    }
}
