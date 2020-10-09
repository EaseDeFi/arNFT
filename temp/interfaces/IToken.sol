pragma experimental ABIEncoderV2;
pragma solidity ^0.6.6;
import "./IERC721.sol";
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

interface IToken is IERC721{
    function tokens(uint256 _nftId) external returns(Token memory);
}
