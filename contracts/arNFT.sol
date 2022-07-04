//TODO: used to be ^0.5.0. Need to check if 0.8.13 can be used without problems
pragma solidity ^0.8.11;

import "./libraries/ERC721Full.sol";
import "./libraries/Ownable.sol";
import "./libraries/ReentrancyGuard.sol";
import "./libraries/SafeERC20.sol";
import "./externals/Externals.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IwNXM.sol";

/** 
    @title Armor NFT
    @dev Armor NFT allows users to purchase Nexus Mutual cover and convert it into 
         a transferable token. It also allows users to swap their Yearn yNFT for Armor arNFT.
    @author ArmorFi -- Robert M.C. Forster, Taek Lee
**/
contract arNFT is
    ERC721Full("ArmorNFT", "arNFT"),
    Ownable,
    ReentrancyGuard {
    
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    bytes4 internal constant ethCurrency = "ETH";
    
    // cover Id => claim Id
    mapping (uint256 => uint256) public claimIds;
    
    // cover Id => cover price
    mapping (uint256 => uint256) public coverPrices;
    
    // cover Id => yNFT token Id.
    // Used to route yNFT submits through their contract.
    // if zero, it is not swapped from yInsure
    mapping (uint256 => uint256) public swapIds;

    // Mapping ("NAME" => smart contract address) of allowed cover currencies.
    mapping (bytes4 => address) public coverCurrencies;

    // indicates if swap for yInsure is available
    // cannot go back to false
    bool public swapActivated;

    // indicates if we use our own NXM to buy cover for msg.sender or if we buy wNXM on spot and unwrap to NXM
    // true = own NXM; false = buy wNXM on spot
    bool public useReserveNXM;

    // Nexus Mutual master contract.
    INXMMaster public nxMaster;

    // yNFT contract that we're swapping tokens from.
    IyInsure public ynft;

    // NXM token.
    IERC20 public nxmToken;

    // wNXM token
    IERC20 public wnxmToken;

    // WETH token
    IERC20 public wethToken;

    // NXM wrapper
    IwNXM public nxmWrapper;

    // Uniswap V2 Router
    IUniswapV2Router02 public uniRouter;

    // Premium that we charge for the cover
    uint8 public premium;

    // // Uniswap V2 Factory
    // IUniswapV2Factory public uniFactory;

    // // Uniswap V2 WETH-WNXM Pair
    // IUniswapV2Pair public wethNxmPair;
    
    enum CoverStatus {
        Active,
        ClaimAccepted,
        ClaimDenied,
        CoverExpired,
        ClaimSubmitted,
        Requested
    }
    
    enum ClaimStatus {
        PendingClaimAssessorVote, // 0
        PendingClaimAssessorVoteDenied, // 1
        PendingClaimAssessorVoteThresholdNotReachedAccept, // 2
        PendingClaimAssessorVoteThresholdNotReachedDeny, // 3
        PendingClaimAssessorConsensusNotReachedAccept, // 4
        PendingClaimAssessorConsensusNotReachedDeny, // 5
        FinalClaimAssessorVoteDenied, // 6
        FinalClaimAssessorVoteAccepted, // 7
        FinalClaimAssessorVoteDeniedMVAccepted, // 8
        FinalClaimAssessorVoteDeniedMVDenied, // 9
        FinalClaimAssessorVotAcceptedMVNoDecision, // 10
        FinalClaimAssessorVoteDeniedMVNoDecision, // 11
        ClaimAcceptedPayoutPending, // 12
        ClaimAcceptedNoPayout, // 13
        ClaimAcceptedPayoutDone // 14
    }

    event SwappedYInsure (
        uint256 indexed yInsureTokenId,
        uint256 indexed coverId
    );

    event ClaimSubmitted (
        uint256 indexed coverId,
        uint256 indexed claimId
    );
    
    event ClaimRedeemed (
        address indexed receiver,
        bytes4 indexed currency,
        uint256 value
    );

    event BuyCover (
        uint indexed coverId,
        address indexed buyer,
        address indexed coveredContract,
        bytes4 currency,
        uint256 coverAmount,
        uint256 coverPrice,
        uint256 startTime,
        uint16 coverPeriod
    );

    
    /**
     * @dev Make sure only the owner of a token or someone approved to transfer it can call.
     * @param _tokenId Id of the token being checked.
    **/
    modifier onlyTokenApprovedOrOwner(uint256 _tokenId) {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Not approved or owner");
        _;
    }

    constructor(address _nxMaster, address _ynft, address _nxmToken, address _wethToken, address _nxmWrapper, address _uniswapV2Router02, address _uniswapV2Factory, uint8 _premium) public {
        nxMaster = INXMMaster(_nxMaster);
        ynft = IyInsure(_ynft);
        nxmToken = IERC20(_nxmToken);
        wnxmToken = IERC20(_wnxmWrapper);
        wethToken = IERC20(_wethToken);
        nxmWrapper = IwNXM(_nxmWrapper);
        uniRouter = IUniswapV2Router02(_uniswapV2Router02);
        premium = _premium;
    }
    
    fallback () payable external {}

    function setUseReserveNXM(
        bool _useReserveNXM
    ) external onlyOwner {
        useReserveNXM = _useReserveNXM;
    }
    
    // Arguments to be passed as coverDetails, from the quote api:
    //    coverDetails[0] = coverAmount;
    //    coverDetails[1] = coverPrice;
    //    coverDetails[2] = coverPriceNXM;
    //    coverDetails[3] = expireTime;
    //    coverDetails[4] = generationTime;
    /**
     * @dev Main function to buy a cover.
     * @param _coveredContractAddress Address of the protocol to buy cover for.
     * @param _coverCurrency bytes4 currency name to buy coverage for.
     * @param _coverPeriod Amount of time to buy cover for.
     * @param _v , _r, _s Signature of the Nexus Mutual API.
    **/
    function buyCoverEthWnxmSpot(
        address _coveredContractAddress,
        bytes4 _coverCurrency,
        uint[] calldata _coverDetails,
        uint16 _coverPeriod,
        uint256 _coverPriceWETH,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
        //TODO: useReserveNXM variable that decides whether we buy wnxm on spot or use our own nxm
    ) external payable {
        uint256 coverPrice = _coverDetails[1];
        uint256 coverPriceNXM = _coverDetails[2];
        address[] memory path = [address(wethToken), address(wnxmToken)];


        uint256[] memory _amountOutMins = uniRouter.getAmountsOut(
            (_coverCurrency == "ETH"? msg.value: _coverPriceWETH),
            path
        );

        require(_amountOutMins[path.length - 1] > (coverPriceNXM * premium), "Incorrect value sent");

        if (_coverCurrency == "ETH") {
            require(_coverPriceWETH == 0, "No WETH required when paying with ETH");
            wethToken.deposit.value(msg.value);
            // TODO: send ETH directly to our address
            wethToken.safeTransferFrom(msg.sender, address(this), msg.value);
        } else {
            IERC20 erc20 = IERC20( coverCurrencies[_coverCurrency] );
            require(erc20 == wethToken, "Only WETH or ETH allowed.");
            require(msg.value == 0, "ETH not required when buying with WETH");
        // TODO: send ETH directly to our address if we use our own NXM to buy cover
            wethToken.safeTransferFrom(msg.sender, address(this), _coverPriceWETH);
        }
        
        if(useReserveNXM == false) {
            // spot sells ETH for wNXM, unwraps wNXM -> NXM to buy cover with NXM
            uint256[] memory _amountOut = uniRouter.swapExactETHForTokens(
                _amountOutMins[path.length - 1],
                path,
                address(this),
                block.timestamp
            );
            
            //TODO: is right index 0 or 1?
            nxmWrapper.unwrap(_amountOut[0]);
            // alt: .unwrapTo
        } else {
            // unwraps wNXM -> NXM to buy cover with NXM
            require(wnxmToken.balanceOf(address(this)) >= coverPriceNXM, "Contract doesn't have enough wNXM");
            nxmWrapper.unwrap(_amountOut[0]);
            // alt: .unwrapTo
        }

        uint256 coverId = _buyCover(_coveredContractAddress, _coverCurrency, _coverDetails, _coverPeriod, _v, _r, _s);
        _mint(msg.sender, coverId);
        
        emit BuyCover(coverId, msg.sender, _coveredContractAddress, _coverCurrency, _coverDetails[0], _coverDetails[1], 
                      block.timestamp, _coverPeriod);
    }

    
    function buyCoverUnwrapWnxm(
        address _coveredContractAddress,
        bytes4 _coverCurrency,
        uint[] calldata _coverDetails,
        uint16 _coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable {
        uint256 coverPrice = _coverDetails[1];

        require(_coverCurrency == "wNXM", "Only buyable with wNXM");
        //TODO: is this the check to see if wNXM has been added to coverCurrencies?
        IERC20 erc20 = IERC20( coverCurrencies[_coverCurrency] );
        require(erc20 != IERC20( address(0) ), "Cover currency is not allowed.");
        require(msg.value == 0, "Eth not required when buying with erc20");

        erc20.safeTransferFrom(msg.sender, address(this), coverPrice);
        nxmWrapper.unwrap(coverPrice);
        uint256 coverId = _buyCover(_coveredContractAddress, _coverCurrency, _coverDetails, _coverPeriod, _v, _r, _s);
        _mint(msg.sender, coverId);
        
        emit BuyCover(coverId, msg.sender, _coveredContractAddress, _coverCurrency, _coverDetails[0], _coverDetails[1], 
                      block.timestamp, _coverPeriod);
    }

    // This function doesn't swap ETH to wNXM but rather uses our reserves wNXM to purchase cover. 
    // TODO: not yet implemented. it's still the same as buyCoverOld
    function buyCoverWnxmReserve(
        address _coveredContractAddress,
        bytes4 _coverCurrency,
        uint[] calldata _coverDetails,
        uint16 _coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable {
        uint256 coverPrice = _coverDetails[1];

        if (_coverCurrency == "ETH") {
            require(msg.value == coverPrice, "Incorrect value sent");
        } else {
            IERC20 erc20 = IERC20( coverCurrencies[_coverCurrency] );
            require(erc20 != IERC20( address(0) ), "Cover currency is not allowed.");

            require(msg.value == 0, "Eth not required when buying with erc20");
            erc20.safeTransferFrom(msg.sender, address(this), coverPrice);
        }
        
        uint256 coverId = _buyCover(_coveredContractAddress, _coverCurrency, _coverDetails, _coverPeriod, _v, _r, _s);
        _mint(msg.sender, coverId);
        
        emit BuyCover(coverId, msg.sender, _coveredContractAddress, _coverCurrency, _coverDetails[0], _coverDetails[1], 
                      block.timestamp, _coverPeriod);
    }

    function buyCoverOld(
        address _coveredContractAddress,
        bytes4 _coverCurrency,
        uint[] calldata _coverDetails,
        uint16 _coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable {
        uint256 coverPrice = _coverDetails[1];

        if (_coverCurrency == "ETH") {
            require(msg.value == coverPrice, "Incorrect value sent");
        } else {
            IERC20 erc20 = IERC20( coverCurrencies[_coverCurrency] );
            require(erc20 != IERC20( address(0) ), "Cover currency is not allowed.");

            require(msg.value == 0, "Eth not required when buying with erc20");
            erc20.safeTransferFrom(msg.sender, address(this), coverPrice);
        }
        
        uint256 coverId = _buyCover(_coveredContractAddress, _coverCurrency, _coverDetails, _coverPeriod, _v, _r, _s);
        _mint(msg.sender, coverId);
        
        emit BuyCover(coverId, msg.sender, _coveredContractAddress, _coverCurrency, _coverDetails[0], _coverDetails[1], 
                      block.timestamp, _coverPeriod);
    }
    
    /**
     * @dev Submit a claim for the NFT after a hack has happened on its protocol.
     * @param _tokenId ID of the token a claim is being submitted for.
    **/
    function submitClaim(uint256 _tokenId) external onlyTokenApprovedOrOwner(_tokenId) {
        // If this was a yNFT swap, we must route the submit through them.
        if (swapIds[_tokenId] != 0) {
            _submitYnftClaim(_tokenId);
            return;
        }
        
        (uint256 coverId, /*uint8 coverStatus*/, /*sumAssured*/, /*coverPeriod*/, /*uint256 validUntil*/) = _getCover2(_tokenId);

        uint256 claimId = _submitClaim(coverId);
        claimIds[_tokenId] = claimId;
        
        emit ClaimSubmitted(coverId, claimId);
    }
    
    /**
     * @dev Redeem a claim that has been accepted and paid out.
     * @param _tokenId Id of the token to redeem claim for.
    **/
    function redeemClaim(uint256 _tokenId) public onlyTokenApprovedOrOwner(_tokenId)  nonReentrant {
        require(claimIds[_tokenId] != 0, "No claim is in progress.");
        
        (/*cid*/, /*memberAddress*/, /*scAddress*/, bytes4 currencyCode, /*sumAssured*/, /*premiumNXM*/) = _getCover1(_tokenId);
        ( , /*uint8 coverStatus*/, uint256 sumAssured, , ) = _getCover2(_tokenId);
        
        require(_payoutIsCompleted(claimIds[_tokenId]), "Claim accepted but payout not completed");
       
        // this will prevent duplicate redeem 
        _burn(_tokenId);
        _sendAssuredSum(currencyCode, sumAssured);
        
        emit ClaimRedeemed(msg.sender, currencyCode, sumAssured);
    }
    
    function activateSwap()
      public
      onlyOwner
    {
        require(!swapActivated, "Already Activated");
        swapActivated = true;
    }

    /**
     * @dev External swap yNFT token for our own. Simple process because we do not need to create cover.
     * @param _ynftTokenId The ID of the token on yNFT's contract.
    **/
    function swapYnft(uint256 _ynftTokenId)
      public
    {
        require(swapActivated, "Swap is not activated yet");
        //this does not returns bool
        ynft.transferFrom(msg.sender, address(this), _ynftTokenId);
        
        (uint256 coverPrice, uint256 coverId, uint256 claimId) = _getCoverAndClaim(_ynftTokenId);

        _mint(msg.sender, coverId);

        swapIds[coverId] = _ynftTokenId;
        claimIds[coverId] = claimId;
        coverPrices[coverId] = coverPrice;
        
        emit SwappedYInsure(_ynftTokenId, coverId);
    }
    
    /**
     * @dev Swaps a batch of yNFT tokens for our own.
     * @param _tokenIds An array of the IDs of the tokens on yNFT's contract.
    **/
    function batchSwapYnft(uint256[] calldata _tokenIds)
      external
    {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            swapYnft(_tokenIds[i]);
        }
    }
    
   /**
     * @dev Owner can approve the contract for any new ERC20 (so we don't need to in every buy).
     * @param _tokenAddress Address of the ERC20 that we want approved.
    **/
    function approveToken(address _tokenAddress)
      external
    {
        IPool1 pool1 = IPool1(nxMaster.getLatestAddress("P1"));
        address payable pool1Address = address(uint160(address(pool1)));
        IERC20 erc20 = IERC20(_tokenAddress);
        erc20.safeApprove( pool1Address, uint256(-1) );
    }
    
    /**
     * @dev Getter for all token info from Nexus Mutual.
     * @param _tokenId of the token to get cover info for (also NXM cover ID).
     * @return All info from NXM about the cover.
    **/
    function getToken(uint256 _tokenId)
      external
      view
    returns (uint256 cid, 
             uint8 status, 
             uint256 sumAssured,
             uint16 coverPeriod, 
             uint256 validUntil, 
             address scAddress, 
             bytes4 currencyCode, 
             uint256 premiumNXM,
             uint256 coverPrice,
             uint256 claimId)
    {
        (/*cid*/, /*memberAddress*/, scAddress, currencyCode, /*sumAssured*/, premiumNXM) = _getCover1(_tokenId);
        (cid, status, sumAssured, coverPeriod, validUntil) = _getCover2(_tokenId);
        coverPrice = coverPrices[_tokenId];
        claimId = claimIds[_tokenId];
    }
    
    /**
     * @dev Get status of a cover claim.
     * @param _tokenId Id of the token we're checking.
     * @return Status of the claim being made on the token.
    **/
    function getCoverStatus(uint256 _tokenId) external view returns (uint8 coverStatus, bool payoutCompleted) {
        (, coverStatus, , , ) = _getCover2(_tokenId);
        payoutCompleted = _payoutIsCompleted(claimIds[_tokenId]);
    }
    
    /**
     * @dev Get address of the NXM Member Roles contract.
     * @return Address of the current Member Roles contract.
    **/
    function getMemberRoles() public view returns (address) {
        return nxMaster.getLatestAddress("MR");
    }
    
    /**
     * @dev Change membership to new address.
     * @param _newMembership Membership address to change to.
    **/
    function switchMembership(address _newMembership) external onlyOwner {
        nxmToken.safeApprove(getMemberRoles(),uint(-1));
        IMemberRoles(getMemberRoles()).switchMembership(_newMembership);
    }
    
    /**
     * @dev Internal function for buying cover--params are same as eponymous external function.
     * @return coverId ID of the new cover that has been bought.
    **/
    function _buyCover(
        address _coveredContractAddress,
        bytes4 _coverCurrency,
        uint[] memory _coverDetails,
        uint16 _coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal returns (uint256 coverId) {
    
        uint256 coverPrice = _coverDetails[1];
        IPool1 pool1 = IPool1(nxMaster.getLatestAddress("P1"));

        if (_coverCurrency == "ETH") {
            pool1.makeCoverBegin.value(coverPrice)(_coveredContractAddress, _coverCurrency, _coverDetails, _coverPeriod, _v, _r, _s);
        } else {
            pool1.makeCoverUsingCA(_coveredContractAddress, _coverCurrency, _coverDetails, _coverPeriod, _v, _r, _s);
        }
    
        IQuotationData quotationData = IQuotationData(nxMaster.getLatestAddress("QD"));
        // *assumes* the newly created claim is appended at the end of the list covers
        coverId = quotationData.getCoverLength().sub(1);
        
        // Keep track of how much was paid for this cover.
        coverPrices[coverId] = coverPrice;
    }
    
    /**
     * @dev Internal submit claim function.
     * @param _coverId on the NXM contract (same as our token ID).
     * @return claimId of the new claim.
    **/
    function _submitClaim(uint256 _coverId) internal returns (uint256) {
        IClaims claims = IClaims(nxMaster.getLatestAddress("CL"));
        claims.submitClaim(_coverId);
    
        IClaimsData claimsData = IClaimsData(nxMaster.getLatestAddress("CD"));
        uint256 claimId = claimsData.actualClaimLength() - 1;
        return claimId;
    }
    
    /**
     * Submits a claim through yNFT if this was a swapped token.
     * @param _tokenId ID of the token on the arNFT contract.
    **/
    function _submitYnftClaim(uint256 _tokenId)
      internal
    {
        uint256 ynftTokenId = swapIds[_tokenId];
        ynft.submitClaim(ynftTokenId);
        
        (/*coverPrice*/, /*coverId*/, uint256 claimId) = _getCoverAndClaim(ynftTokenId);
        claimIds[_tokenId] = claimId;
    }

    /**
     * @dev Check whether the payout of a claim has occurred.
     * @param _claimId ID of the claim we are checking.
     * @return True if claim has been paid out, false if not.
    **/
    function _payoutIsCompleted(uint256 _claimId) internal view returns (bool) {
        uint256 status;
        IClaims claims = IClaims(nxMaster.getLatestAddress("CL"));
        (, status, , , ) = claims.getClaimbyIndex(_claimId);
        return status == uint256(ClaimStatus.ClaimAcceptedPayoutDone);
    }

    /**
     * @dev Send tokens after a successful redeem claim.
     * @param _coverCurrency bytes4 of the currency being used.
     * @param _sumAssured The amount of the currency to send.
    **/
    function _sendAssuredSum(bytes4 _coverCurrency, uint256 _sumAssured) internal {
        uint256 claimReward;

        if (_coverCurrency == ethCurrency) {
            claimReward = _sumAssured * (10 ** 18);
            msg.sender.transfer(claimReward);
        } else {
            IERC20 erc20 = IERC20( coverCurrencies[_coverCurrency] );
            require (erc20 != IERC20( address(0) ), "Cover currency is not allowed.");

            uint256 decimals = uint256(erc20.decimals());
            claimReward = _sumAssured * (10 ** decimals);
            erc20.safeTransfer(msg.sender, claimReward);
        }
    }
    
    /**
     * @dev Get the cover Id and claim Id of the token from the ynft contract.
     * @param _ynftTokenId The Id of the token on the ynft contract.
    **/
    function _getCoverAndClaim(uint256 _ynftTokenId)
      internal
    returns (uint256 coverPrice, uint256 coverId, uint256 claimId)
    {
       ( , , , coverPrice, , , , coverId, , claimId) = ynft.tokens(_ynftTokenId);
    }
    
    /**
     * @dev Get (some) cover details from the NXM contracts.
     * @param _coverId ID of the cover to get--same as our token ID.
     * @return Details about the token.
    **/
    function _getCover1 (
        uint256 _coverId
    ) internal view returns (
        uint256 cid,
        address memberAddress,
        address scAddress,
        bytes4 currencyCode,
        uint256 sumAssured,
        uint256 premiumNXM
    ) {
        IQuotationData quotationData = IQuotationData(nxMaster.getLatestAddress("QD"));
        return quotationData.getCoverDetailsByCoverID1(_coverId);
    }
    
    /**
     * @dev Get the rest of the cover details from NXM contracts.
     * @param _coverId ID of the cover to get--same as our token ID.
     * @return 2nd set of details about the token.
    **/
    function _getCover2 (
        uint256 _coverId
    ) internal view returns (
        uint256 cid,
        uint8 status,
        uint256 sumAssured,
        uint16 coverPeriod,
        uint256 validUntil
    ) {
        IQuotationData quotationData = IQuotationData(nxMaster.getLatestAddress("QD"));
        return quotationData.getCoverDetailsByCoverID2(_coverId);
    }
    
    //TODO: change public to external to safe gas
    /**
     * @dev Approve an address to spend NXM tokens from the contract.
     * @param _spender Address to be approved.
     * @param _value The amount of NXM to be approved.
    **/
    function nxmTokenApprove(address _spender, uint256 _value) public onlyOwner {
        nxmToken.safeApprove(_spender, _value);
    }

    //TODO: change public to external to safe gas
    /**
     * @dev Add an allowed cover currency to the arNFT system if one is added to Nexus Mutual.
     * @param _coverCurrency Address of the cover currency to add.
    **/
    function addCurrency(bytes4 _coverCurrency, address _coverCurrencyAddress) public onlyOwner {
        require(coverCurrencies[_coverCurrency] == address(0), "Cover currency already exists.");
        coverCurrencies[_coverCurrency] = _coverCurrencyAddress;
    }

}
