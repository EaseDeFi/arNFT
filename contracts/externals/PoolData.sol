pragma solidity ^0.5.0;

interface IPoolData {

    struct ApiId {
        bytes4 typeOf;
        bytes4 currency;
        uint id;
        uint64 dateAdd;
        uint64 dateUpd;
    }

    struct CurrencyAssets {
        address currAddress;
        uint baseMin;
        uint varMin;
    }

    struct InvestmentAssets {
        address currAddress;
        bool status;
        uint64 minHoldingPercX100;
        uint64 maxHoldingPercX100;
        uint8 decimals;
    }

    struct IARankDetails {
        bytes4 maxIACurr;
        uint64 maxRate;
        bytes4 minIACurr;
        uint64 minRate;
    }

    struct McrData {
        uint mcrPercx100;
        uint mcrEther;
        uint vFull; //Pool funds
        uint64 date;
    }

    function setCapReached(uint val) external;
    function getInvestmentAssetDecimals(bytes4 curr) external returns(uint8 decimal);
    function getCurrencyAssetAddress(bytes4 curr) external view returns(address);
    function getInvestmentAssetAddress(bytes4 curr) external view returns(address);
    function getInvestmentAssetStatus(bytes4 curr) external view returns(bool status);
}
