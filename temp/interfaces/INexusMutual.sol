pragma solidity ^0.6.6;

/**
 * @dev Quick interface for the Nexus Mutual contract to work with the Armor Contracts.
 **/

interface INexusMutual {
    function submitClaim(uint256 _nftId) external;
    function redeemClaim(uint256 _nftId) external;
}
// to get nexus mutual contract address
interface INXMMaster {
    function tokenAddress() external view returns(address);
    function owner() external view returns(address);
    function pauseTime() external view returns(uint);
    function masterInitialized() external view returns(bool);
    function isPause() external view returns(bool check);
    function isMember(address _add) external view returns(bool);
    function getLatestAddress(bytes2 _contractName) external view returns(address payable contractAddress);
}

interface QuotationData {

    enum HCIDStatus { NA, kycPending, kycPass, kycFailedOrRefunded, kycPassNoCover }
    enum CoverStatus { Active, ClaimAccepted, ClaimDenied, CoverExpired, ClaimSubmitted, Requested }

    struct Cover {
        address payable memberAddress;
        bytes4 currencyCode;
        uint sumAssured;
        uint16 coverPeriod;
        uint validUntil;
        address scAddress;
        uint premiumNXM;
    }

    struct HoldCover {
        uint holdCoverId;
        address payable userAddress;
        address scAddress;
        bytes4 coverCurr;
        uint[] coverDetails;
        uint16 coverPeriod;
    }

    function getCoverLength() external returns(uint len);
    function getAuthQuoteEngine() external returns(address _add);
    function getAllCoversOfUser(address _add) external returns(uint[] memory allCover);
    function getUserCoverLength(address _add) external returns(uint len);
    function getCoverStatusNo(uint _cid) external returns(uint8);
    function getCoverPeriod(uint _cid) external returns(uint32 cp);
    function getCoverSumAssured(uint _cid) external returns(uint sa);
    function getCurrencyOfCover(uint _cid) external returns(bytes4 curr);
    function getValidityOfCover(uint _cid) external returns(uint date);
    function getscAddressOfCover(uint _cid) external returns(uint, address);
    function getCoverMemberAddress(uint _cid) external returns(address payable _add);
    function getCoverPremiumNXM(uint _cid) external returns(uint _premiumNXM);
    function getCoverDetailsByCoverID1(
        uint _cid
    )
    external
    returns (
        uint cid,
        address _memberAddress,
        address _scAddress,
        bytes4 _currencyCode,
        uint _sumAssured,
        uint premiumNXM
    );
    function getCoverDetailsByCoverID2(
        uint _cid
    )
    external
    view
    returns (
        uint cid,
        uint8 status,
        uint sumAssured,
        uint16 coverPeriod,
        uint validUntil
    );
    function getHoldedCoverDetailsByID1(
        uint _hcid
    )
    external
    view
    returns (
        uint hcid,
        address scAddress,
        bytes4 coverCurr,
        uint16 coverPeriod
    );
    function getUserHoldedCoverLength(address _add) external returns (uint);
    function getUserHoldedCoverByIndex(address _add, uint index) external returns (uint);
    function getHoldedCoverDetailsByID2(
        uint _hcid
    )
    external
    returns (
        uint hcid,
        address payable memberAddress,
        uint[] memory coverDetails
    );
    function getTotalSumAssuredSC(address _add, bytes4 _curr) external returns(uint amount);

}

