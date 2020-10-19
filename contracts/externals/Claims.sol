pragma solidity ^0.5.0;

interface IClaims {
    function getClaimbyIndex(uint _claimId) external view returns (
        uint claimId,
        uint status,
        int8 finalVerdict,
        address claimOwner,
        uint coverId
    );
    function submitClaim(uint coverId) external;
}
