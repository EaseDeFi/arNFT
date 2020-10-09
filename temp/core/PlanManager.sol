pragma solidity ^0.6.6;
import './StakeManager.sol';
import './BalanceManager.sol';
import '../general/MerkleProof.sol';
/**
 * @dev Separating this off to specifically keep track of a borrower's plans.
**/
contract PlanManager {
    
    // List of plans that a user has purchased so there is a historical record.
    mapping (address => Plan[]) public plans;
    
    // StakeManager calls this when a new NFT is added to update what the price for that protocol is.
    // Cover price in DAI (1e18) of price per second per DAI covered.
    /**
     * @notice Figure this out with new bytes32 protocol structure.
    **/
    // CHECK: is it ok to keccak(protocol, coverCurrency)?
    mapping (bytes32 => uint256) public ynftCoverPrice;
    
    // Mapping to keep track of how much coverage we've sold for each protocol.
    // keccak256(protocol, coverCurrency) => total borrowed cover
    mapping (bytes32 => uint256) public totalBorrowedAmount;

    mapping (bytes32 => uint256) public totalUsedCover;
    
    // The amount of markup for Armor's service vs. the original cover cost.
    uint256 public markup;

    StakeManager public stakeManager;
    BalanceManager public balanceManager;
    
    // Mapping = protocol => cover amount
    /**
     * @notice  Does this timestamp need to be over a certain amount of time?
     *          this may be able to be put off for now.
    **/
    struct Plan {
        uint128 startTime;
        uint128 endTime;
        bytes32 merkleRoot;
    }

    constructor(
        address _stakeManager,
        address _balanceManager
    ) public {
        stakeManager = StakeManager(_stakeManager);
        balanceManager = BalanceManager(_balanceManager);
    }

    modifier onlyStakeManager() {
        require(msg.sender == address(stakeManager), "Only StakeManager can call this function");
        _;
    }
    
    /**
     * @dev User can update their plan for cover amount on any protocol.
     * @param _protocols Addresses of the protocols that we want coverage for.
     * @param _coverAmounts The amount of coverage desired in FULL DAI (0 decimals).
     * @notice Let's simplify this somehow--even just splitting into different functions.
    **/
    function updatePlan(bytes32[] calldata _oldProtocols, uint256[] calldata _oldCoverAmounts, bytes32[] calldata _protocols, uint256[] calldata _coverAmounts)
      external
    {
        // Need to get price of the protocol here
        require(_protocols.length == _coverAmounts.length, "Input array lengths do not match.");
        Plan storage lastPlan = plans[msg.sender][plans[msg.sender].length - 1];
        require(_generateMerkleRoot(_oldProtocols, _oldCoverAmounts) == lastPlan.merkleRoot, "Invalid old values merkleRoot different");
        address user = msg.sender;
        
        // This reverts on not enough cover. Only do check in actual update to avoid multiple loops checking coverage.
        updateTotals(_oldProtocols, _oldCoverAmounts, _protocols, _coverAmounts);
        
        uint256 newPricePerSec;
        uint256 _markup = markup;
        
        // Loop through protocols, find price per second, add to rate, add coverage amount to mapping.
        for (uint256 i = 0; i < _protocols.length; i++) {
            // Amount of DAI that must be paid per DAI of coverage per second.
            uint256 pricePerSec = ynftCoverPrice[ _protocols[i] ] * _coverAmounts[i] * _markup;
            newPricePerSec += pricePerSec;
        }

        /**
         * @dev can for sure separate this shit into another function.
        **/
        uint256 balance = balanceManager.balanceOf(user);
        uint256 endTime = balance / newPricePerSec + now;
        
        // Set old plan to have ended now.
        lastPlan.endTime = uint128(block.timestamp);

        bytes32 merkleRoot = _generateMerkleRoot(_protocols, _coverAmounts);
        Plan memory newPlan;
        newPlan = Plan(uint128(now), uint128(endTime), merkleRoot);
        plans[user].push(newPlan);
        
        // update balance price per second here
        // They get the same price per second as long as they ke
    }

    // should be sorted merkletree. should be calculated off chain
    function _generateMerkleRoot(bytes32[] memory _protocols, uint256[] memory _coverAmounts) internal returns (bytes32){
        require(_protocols.length == _coverAmounts.length, "protocol and coverAmount length mismatch");
        bytes32[] memory leaves = new bytes32[](_protocols.length);
        for(uint256 i = 0 ; i<_protocols.length; i++){
            bytes32 leaf = keccak256(abi.encodePacked(_protocols[i],_coverAmounts[i]));
            leaves[i] = leaf;
        }
        return MerkleProof.calculateRoot(leaves);
    }
    
    /**
     * @dev Update the contract-wide totals for each protocol that has changed.
     * @notice I don't like this, how can it be better?
    **/
    function updateTotals(bytes32[] memory _oldProtocols, uint256[] memory _oldCoverAmounts, bytes32[] memory _newProtocols, uint256[] memory _newCoverAmounts)
      internal
    {
        // Loop through all last covered protocols and amounts
        //mapping(bytes32=>uint256) memory oldCoverAmounts = _oldPlan.coverAmounts;
        //uint256[] memory oldProtocols = _oldPlan.protocols;
    
        // First go through and subtract all old cover amounts.
        for (uint256 i = 0; i < _oldProtocols.length; i++) {
            bytes32 protocol = _oldProtocols[i];
            totalUsedCover[protocol] -= _oldCoverAmounts[i];
        }
        
        // Then go through, add new cover amounts, and make sure they do not pass cover allowed.
        for (uint256 i = 0; i < _newProtocols.length; i++) {
            totalUsedCover[_newProtocols[i]] += _newCoverAmounts[i];
            // Check StakeManager to ensure the new total amount does not go above the staked amount.
            require(stakeManager.allowedCover(_newProtocols[i], totalUsedCover[_newProtocols[i]]));
        }
    }
    
    /**
     * @dev Used by ClaimManager to check how much coverage the user had at the time of a hack.
     * @param _user The user to check coverage for.
     * @param _protocol The address of the protocol that was hacked. (Address used according to yNFT).
     * @param _hackTime The timestamp of when a hack happened.
     * return The amount of coverage the user had at the time--0 if none.
    **/
    function checkCoverage(address _user, bytes32 _protocol, uint256 _hackTime)
      external
      // Make sure we update balance if needed
    returns (uint256)
    {
        // TODO change this to verifying merkle proof
//        // This may be more gas efficient if we don't grab this first but instead grab each plan from storage individually?
//        Plan[] memory planArray = plans[_user];
//        
//        // In normal operation, this for loop should never get too big.
//        // If it does (from malicious action), the user will be the only one to suffer.
//        for (uint256 i = planArray.length - 1; i >= 0; i--) {
//            
//            Plan memory plan = planArray[i];
//            
//            // Only one plan will be active at the time of a hack--return cover amount from then.
//            if (_hackTime >= plan.startTime && _hackTime <= plan.endTime) {
//                
//                uint256 coverAmount = plan.coverAmounts[_protocol];
//                plan.coverAmounts[_protocol] = 0;
//                return coverAmount;
//            
//            }
//            
//        }
        
        return 0;
    }
    
    /**
     * @dev Armor has the ability to change the price that a user is paying for their insurance.
     * @param _protocol The protocol whose yNFT price is being updated.
     * @param _newPrice the new price PER BLOCK that the user will be paying.
    **/
    function changePrice(bytes32 _protocol, uint256 _newPrice)
      external
      onlyStakeManager
    {
        ynftCoverPrice[_protocol] = _newPrice;
    }
    
}
