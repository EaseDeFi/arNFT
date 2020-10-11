pragma solidity ^0.5.0;

import "./libraries/ERC721Full.sol";
import "./libraries/Ownable.sol";
import "./libraries/ReentrancyGuard.sol";
import "./externals/Externals.sol";
import "./interfaces/IERC20.sol";
/**
 * @dev All commented out lines in yInsure were changed for the arNFT implementation.
**/
contract arInsure is
    ERC721Full("ArmorNFT", "arNFT"),
    Ownable,
    ReentrancyGuard {
    
    using SafeMath for uint;
    
    bytes4 internal constant ethCurrency = "ETH";
    
    // arNFT claim IDs because we won't have a struct for this.
    // cover Id => claim Id
    mapping (uint256 => uint256) public claimIds;
    
    // cover ID => yNFT token id. Will be 0 if it was not a swap.
    // Used to route yNFT submits through their contract.
    mapping(uint256 => uint256) public swapIds;
    
    //INXMMaster constant public nxMaster = INXMMaster(0x01BFd82675DBCc7762C84019cA518e701C0cD07e);
    INXMMaster public nxMaster;

    // yNFT contract that we're swapping tokens from.
    //IyInsure constant public ynft = IyInsure(0x181Aea6936B407514ebFC0754A37704eB8d98F91);
    IyInsure public ynft;
    
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
    
    event ClaimRedeemed (
        address receiver,
        uint value,
        bytes4 currency
    );
    
    /**
     * @dev Make sure only the owner of a token or someone approved to transfer it can call.
     * @param tokenId Id of the token being checked.
    **/
    modifier onlyTokenApprovedOrOwner(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved or owner");
        _;
    }

    constructor(address _nxMaster, address _ynft) public {
        nxMaster = INXMMaster(_nxMaster);
        ynft = IyInsure(_ynft);
    }
    
    function () payable external {}
    
    // Arguments to be passed as coverDetails, from the quote api:
    //    coverDetails[0] = coverAmount;
    //    coverDetails[1] = coverPrice;
    //    coverDetails[2] = coverPriceNXM;
    //    coverDetails[3] = expireTime;
    //    coverDetails[4] = generationTime;
    /**
     * @dev Main function to buy a cover.
     * @param coveredContractAddress Address of the protocol to buy cover for.
     * @param coverCurrency bytes4 currency name to buy coverage for.
     * @param coverPeriod Amount of time to buy cover for.
     * @param _v , _r, _s Signature of the Nexus Mutual API.
    **/
    function buyCover(
        address coveredContractAddress,
        bytes4 coverCurrency,
        uint[] calldata coverDetails,
        uint16 coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external payable {
        uint coverPrice = coverDetails[1];

        if (coverCurrency == "ETH") {

            require(msg.value == coverPrice, "Incorrect value sent");
            
        } else {

            IERC20 erc20 = IERC20(_getCurrencyAssetAddress(coverCurrency));

            require(msg.value == 0, "Eth not required when buying with erc20");  // TODO check failure case
            require(erc20.transferFrom(msg.sender, address(this), coverPrice), "Transfer failed");
        
        }
        
        uint coverId = _buyCover(coveredContractAddress, coverCurrency, coverDetails, coverPeriod, _v, _r, _s);

        _mint(msg.sender, coverId);
    }
    
    /**
     * @dev Submit a claim for the NFT after a hack has happened on its protocol.
     * @param tokenId ID of the token a claim is being submitted for.
    **/
    function submitClaim(uint256 tokenId) external onlyTokenApprovedOrOwner(tokenId) {

        // If this was a yNFT swap, we must route the submit through them.
        if (swapIds[tokenId] != 0) {
            
            _submitYnftClaim(tokenId);
            return;

        }
        
        (uint256 coverId, uint8 coverStatus, /*sumAssured*/, /*coverPeriod*/, uint256 validUntil) = _getCover2(tokenId);
            
        if (claimIds[tokenId] > 0) {
            
            require(coverStatus == uint8(CoverStatus.ClaimDenied),
            "Can submit another claim only if the previous one was denied.");
            
        }
        
        // A submission until it has expired + a defined amount of time.
        require(validUntil + _getLockTokenTimeAfterCoverExpiry() >= block.timestamp, "Token is expired"); //TODO check expired case
        
        uint256 claimId = _submitClaim(coverId);
        claimIds[tokenId] = claimId;
    }
    
    /**
     * @dev Redeem a claim that has been accepted and paid out.
     * @param tokenId Id of the token to redeem claim for.
    **/
    function redeemClaim(uint256 tokenId) public onlyTokenApprovedOrOwner(tokenId)  nonReentrant {
        require(claimIds[tokenId] != 0, "No claim is in progress.");
        
        (/*cid*/, /*memberAddress*/, /*scAddress*/, bytes4 currencyCode, /*sumAssured*/, /*premiumNXM*/) = _getCover1(tokenId);
        ( , uint8 coverStatus, uint256 sumAssured, , ) = _getCover2(tokenId);
        
        require(coverStatus == uint8(CoverStatus.ClaimAccepted), "Claim is not accepted");
        require(_payoutIsCompleted(claimIds[tokenId]), "Claim accepted but payout not completed"); //TODO check failed case
        
        _burn(tokenId);
        
        _sendAssuredSum(currencyCode, sumAssured);
        
        emit ClaimRedeemed(msg.sender, sumAssured, currencyCode);
    }
    
    /**
     * @dev External swap yNFT token for our own. Simple process because we do not need to create cover.
     * @param _ynftTokenId The ID of the token on yNFT's contract.
    **/
    function swapYnft(uint256 _ynftTokenId)
      public
    {
        require(ynft.transferFrom(msg.sender, address(this), _ynftTokenId), "yNFT was not successfully transferred.");
        
        (uint256 coverId, /*claimId*/) = _getCoverAndClaim(_ynftTokenId);

        _mint(msg.sender, coverId);

        swapIds[coverId] = _ynftTokenId;
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
     *      Added with arNFT.
     * @param _tokenAddress Address of the ERC20 that we want approved.
    **/
    function approveToken(address _tokenAddress)
      external
    {
        Pool1 pool1 = Pool1(nxMaster.getLatestAddress("P1"));
        address payable pool1Address = address(uint160(address(pool1)));
        IERC20 erc20 = IERC20(_tokenAddress);
        erc20.approve( pool1Address, uint256(-1) );
    }
    
    /**
     * @dev Added by arNFT.
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
             uint256 premiumNXM)
    {
        (/*cid*/, /*memberAddress*/, scAddress, currencyCode, /*sumAssured*/, premiumNXM) = _getCover1(_tokenId);
        (cid, status, sumAssured, coverPeriod, validUntil) = _getCover2(_tokenId);
    }
    
    /**
     * @dev Get status of a cover claim.
     * @param tokenId Id of the token we're checking.
     * @return Status of the claim being made on the token.
    **/
    function getCoverStatus(uint256 tokenId) external view returns (uint8 coverStatus, bool payoutCompleted) {//TODO test this
        (, coverStatus, , , ) = _getCover2(tokenId);
        
        payoutCompleted = _payoutIsCompleted(claimIds[tokenId]);
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
    function switchMembership(address _newMembership) external onlyOwner { //TODO test this
        NXMToken nxmToken = NXMToken(nxMaster.tokenAddress());
        nxmToken.approve(getMemberRoles(),uint(-1));
        MemberRoles(getMemberRoles()).switchMembership(_newMembership);
    }
    
    /**
     * @dev Internal function for buying cover--params are same as eponymous external function.
     * @return coverId ID of the new cover that has been bought.
    **/
    function _buyCover(
        address coveredContractAddress,
        bytes4 coverCurrency,
        uint[] memory coverDetails,
        uint16 coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) internal returns (uint coverId) {
    
        uint coverPrice = coverDetails[1];
        Pool1 pool1 = Pool1(nxMaster.getLatestAddress("P1"));

        if (coverCurrency == "ETH") {

            pool1.makeCoverBegin.value(coverPrice)(coveredContractAddress, coverCurrency, coverDetails, coverPeriod, _v, _r, _s);

        } else {

            pool1.makeCoverUsingCA(coveredContractAddress, coverCurrency, coverDetails, coverPeriod, _v, _r, _s);

        }
    
        QuotationData quotationData = QuotationData(nxMaster.getLatestAddress("QD"));

        // *assumes* the newly created claim is appended at the end of the list covers
        coverId = quotationData.getCoverLength().sub(1);
    }
    
    /**
     * @dev Internal submit claim function.
     * @param coverId on the NXM contract (same as our token ID).
     * @return claimId of the new claim.
    **/
    function _submitClaim(uint coverId) internal returns (uint) {
        Claims claims = Claims(nxMaster.getLatestAddress("CL"));
        claims.submitClaim(coverId);
    
        ClaimsData claimsData = ClaimsData(nxMaster.getLatestAddress("CD"));
        uint claimId = claimsData.actualClaimLength() - 1;
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
        
        (/*coverId*/, uint256 claimId) = _getCoverAndClaim(ynftTokenId);
        claimIds[_tokenId] = claimId;
    }

    /**
     * @dev Check whether the payout of a claim has occurred.
     * @param claimId ID of the claim we are checking.
     * @return True if claim has been paid out, false if not.
    **/
    function _payoutIsCompleted(uint claimId) internal view returns (bool) {
        uint256 status;
        Claims claims = Claims(nxMaster.getLatestAddress("CL"));
        (, status, , , ) = claims.getClaimbyIndex(claimId);
        return status == uint(ClaimStatus.FinalClaimAssessorVoteAccepted)
            || status == uint(ClaimStatus.ClaimAcceptedPayoutDone);
    }

    /**
     * @dev Send tokens after a successful redeem claim.
     * @param coverCurrency bytes4 of the currency being used.
     * @param sumAssured The amount of the currency to send.
     * @notice I think this has no decimals?
    **/
    function _sendAssuredSum(bytes4 coverCurrency, uint sumAssured) internal {
        uint256 claimReward;

        if (coverCurrency == ethCurrency) {
            
            claimReward = sumAssured * (10 ** 18);
            msg.sender.transfer(claimReward);
            
        } else {
            
            IERC20 erc20 = IERC20(_getCurrencyAssetAddress(coverCurrency));
            uint256 decimals = uint256(erc20.decimals())
        
            claimReward = sumAssured * (10 ** decimals);
            require(erc20.transfer(msg.sender, claimReward), "Transfer failed"); //TODO not necessary
        
        }
    }
    
    /**
     * @dev Get the cover Id and claim Id of the token from the ynft contract.
     * @param _ynftTokenId The Id of the token on the ynft contract.
    **/
    function _getCoverAndClaim(uint256 _ynftTokenId)
      internal
    returns (uint256 coverId, uint256 claimId)
    {
       ( , , , , , , , coverId, , claimId) = ynft.tokens(_ynftTokenId);
    }
    
    /**
     * @dev Get (some) cover details from the NXM contracts.
     * @param coverId ID of the cover to get--same as our token ID.
     * @return Details about the token.
    **/
    //function getCover(
    function _getCover1 (
        uint coverId
    ) internal view returns (
        uint cid,
        address memberAddress,
        address scAddress,
        bytes4 currencyCode,
        uint256 sumAssured,
        uint256 premiumNXM
    ) {
        QuotationData quotationData = QuotationData(nxMaster.getLatestAddress("QD"));
        return quotationData.getCoverDetailsByCoverID1(coverId);
    }
    
    /**
     * @dev All new. Get the rest of the cover details from NXM contracts.
     * @param coverId ID of the cover to get--same as our token ID.
     * @return 2nd set of details about the token.
    **/
    function _getCover2 (
        uint coverId
    ) internal view returns (
        uint cid,
        uint8 status,
        uint sumAssured,
        uint16 coverPeriod,
        uint validUntil
    ) {
        QuotationData quotationData = QuotationData(nxMaster.getLatestAddress("QD"));
        return quotationData.getCoverDetailsByCoverID2(coverId);
    }
    
    /**
     * @dev Get current address of the desired currency.
     * @param currency bytes4 currencyCode of the currency in question.
     * @return Address of the currency in question.
    **/
    function _getCurrencyAssetAddress(bytes4 currency) internal view returns (address) {
        PoolData pd = PoolData(nxMaster.getLatestAddress("PD"));
        return pd.getCurrencyAssetAddress(currency);
    }
    
    /**
     * @dev Get address of the NXM token.
     * @return Current NXM token address.
    **/
    function _getTokenAddress() internal view returns (address) {
        return nxMaster.tokenAddress();
    }
    
    /**
     * @dev Get the amount of time that a token can still be redeemed after it expires.
    **/
    function _getLockTokenTimeAfterCoverExpiry() internal returns (uint) {
        TokenData tokenData = TokenData(nxMaster.getLatestAddress("TD"));
        return tokenData.lockTokenTimeAfterCoverExp();
    }
    
    function nxmTokenApprove(address _spender, uint256 _value) public onlyOwner {
        IERC20 nxmToken = IERC20(_getTokenAddress());
        nxmToken.approve(_spender, _value);
    }
}
