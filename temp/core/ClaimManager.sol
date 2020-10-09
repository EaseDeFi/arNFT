pragma experimental ABIEncoderV2;
pragma solidity ^0.6.6;

import '../general/Ownable.sol';
import '../interfaces/IERC20.sol';
import '../interfaces/IERC721.sol';
import '../interfaces/INexusMutual.sol';
import '../interfaces/IToken.sol';
import './PlanManager.sol';

/**
 * @dev This contract holds all NFTs. The only time it does something is if a user requests a claim.
 * @notice We need to make sure a user can only claim when they have balance.
**/
contract ClaimManager is Ownable {
    bytes4 public constant ETH_SIG = bytes4(0x45544800);
    bytes4 public constant DAI_SIG = bytes4(0x44414900);
    
    // this is actually going to be the yinsure contract.
    INexusMutual public nexusMutual;
    
    IERC20 public daiContract;

    PlanManager public planManager;

    // Mapping of hacks that we have confirmed to have happened. (keccak256(protocol ID, timestamp) => didithappen).
    mapping (bytes32 => bool) confirmedHacks;
    
    // Emitted when a new hack has been recorded.
    event ConfirmedHack(bytes32 indexed hackId, bytes32 indexed protocol, uint256 timestamp);

    // Emitted when a user successfully receives a payout.
    event ClaimPayout(bytes32 indexed hackId, address indexed user, uint256 amount);
    
    /**
     * @dev Start the contract off by giving it the address of Nexus Mutual to submit a claim.
     * @dev _nexusMutual Address of the Nexus Mutual contract.
     * @dev _daiContract Address of the Dai contract.
    **/
    constructor(address _nexusMutual, address _daiContract, address _planManager)
      public
    {
        nexusMutual = INexusMutual(_nexusMutual);
        daiContract = IERC20(_daiContract);
        planManager = PlanManager(_planManager);
    }
    
    /**
     * @dev User requests claim based on a loss.
     *      Do we want this to be callable by anyone or only the person requesting?
     * @param _hackTime The given timestamp for when the hack occurred.
     * @notice Make sure this cannot be done twice. I also think this protocol interaction can be simplified.
    **/
    function redeemClaim(address _protocolAddress, bytes4 _coverCurrency, uint256 _hackTime)
      external
    {
        bytes32 protocol = keccak256(abi.encodePacked(_protocolAddress, _coverCurrency));
        
        bytes32 hackId = keccak256(abi.encodePacked(protocol, _hackTime));
        require(confirmedHacks[hackId], "No hack with these parameters has been confirmed.");
        
        // Gets the coverage amount of the user at the time the hack happened.
        uint256 coverage = planManager.checkCoverage(msg.sender, protocol, _hackTime);
        
        require(coverage > 0, "User had no coverage at the time of this hack.");
    
        /**
         * @notice Coverage amount is weird. On yNFT it's 0 decimals so we must make sure we account for that.
        **/
    
        // Add Wei to these amounts.
        if (_coverCurrency == DAI_SIG) {
            //TODO change to safeTransfer
            require(daiContract.transfer(msg.sender, coverage), "DAI transfer was unsuccessful");
        }
        else {
            msg.sender.transfer(coverage);
        }

        emit ClaimPayout(hackId, msg.sender, coverage);
    }
    
    /**
     * @dev Submit any NFT that was active at the time of a hack on its protocol.
     * @param _nftId ID of the NFT to submit.
     * @param _protocol Address of the protocol the hack occurred on.
     * @param _hackTime The timestamp of the hack that occurred.
     * @notice I think this _protocol/_protocolAddress use can be simplified.
    **/
    function submitNft(uint256 _nftId, bytes32 _protocol, address _protocolAddress, uint256 _hackTime)
      external
    {
        bytes32 hackId = keccak256(abi.encodePacked(_protocol, _hackTime));
        require(confirmedHacks[hackId], "No hack with these parameters has been confirmed.");

        // require ynft has not been claimed
        Token memory token = IToken(address(nexusMutual)).tokens(_nftId);
        
        // Make sure yNFT was not expired.
        
        // require ynft matches the protocol
        
        /**
         * @notice I don't think you can get protocol from the yNFT contracts, only NXM.
        **/
        
        // require ynft was active at the time of the hack
        // PlanManager

        nexusMutual.submitClaim(_nftId);
    }
    
    /**
     * @dev Calls the yInsure contract to redeem a claim (receive funds) if it has been accepted.
     *      This is callable by anyone without any checks--either we receive money or it reverts.
     * @param _nftId The ID of the yNft token.
    **/
    function redeemNft(uint256 _nftId)
      external
    {
        nexusMutual.redeemClaim(_nftId);
    }
    
    /**
     * @dev Called by Armor for now--we confirm a hack happened and give a timestamp for what time it was.
     * @param _protocol The address of the protocol that has been hacked (address that would be on yNFT).
     * @param _hackTime The timestamp of the time the hack occurred.
    **/
    function confirmHack(bytes32 _protocol, uint256 _hackTime)
      external
      onlyOwner
    {
        bytes32 hackId = keccak256(abi.encodePacked(_protocol, _hackTime));
        confirmedHacks[hackId] = true;
        
        emit ConfirmedHack(hackId, _protocol, _hackTime);
    }
    
}
