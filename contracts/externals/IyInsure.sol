pragma solidity ^0.5.0;

interface IyInsure {
    struct Token {
        uint expirationTimestamp;
        bytes4 coverCurrency;
        uint coverAmount;
        uint coverPrice;
        uint coverPriceNXM;
        uint expireTime;
        uint generationTime;
        uint coverId;
        bool claimInProgress;
        uint claimId;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function submitClaim(uint256 tokenId) external;
    function tokens(uint256 tokenId) external returns (uint, bytes4, uint, uint, uint, uint, uint, uint, bool, uint);
}
