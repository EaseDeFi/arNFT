pragma solidity ^0.5.0;
interface IarNFT{
  function balanceOf(address owner) external view returns (uint256 balance);
  function ownerOf(uint256 tokenId) external view returns (address owner);
  function safeTransferFrom(address from, address to, uint256 tokenId) external;
  function transferFrom(address from, address to, uint256 tokenId) external;
  function approve(address to, uint256 tokenId) external;
  function getApproved(uint256 tokenId) external view returns (address operator);
  function setApprovalForAll(address operator, bool _approved) external;
  function isApprovedForAll(address owner, address operator) external view returns (bool);
  function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

  function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function tokenURI(uint256 tokenId) external view returns (string memory);
  function claimIds(uint256 coverId) external view returns(uint256);
  function coverPrices(uint256 coverId) external view returns(uint256);
  function swapIds(uint256 coverId) external view returns(uint256);
  function swapActivated() external view returns(bool);
  function nxMaster() external view returns(address);
  function ynft() external view returns(address);
  function buyCover(
    address _coveredContractAddress,
    bytes4 _coverCurrency,
    uint[] calldata _coverDetails,
    uint16 _coverPeriod,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) external payable;
  function submitClaim(uint256 coverId) external;
  function redeemClaim(uint256 coverId) external;
  function activateSwap(uint256 coverId) external;
  function swapYnft(uint256 ynftId) external;
  function batchSwapYnft(uint256[] calldata _tokenIds) external;
  function approveToken(address _tokenAddress) external;
  function getToken(uint256 _tokenId)
    external
    view
  returns (
    uint256 cid, 
    uint8 status, 
    uint256 sumAssured,
    uint16 coverPeriod, 
    uint256 validUntil, 
    address scAddress, 
    bytes4 currencyCode, 
    uint256 premiumNXM,
    uint256 coverPrice,
    uint256 claimId
  );
  function getCoverStatus(uint256 coverId) external view returns(uint8 coverStatus, bool payoutCompleted);
  function getMemberRoles() external view returns(address);
  function switchMembership(address newMember) external;
  function nxmTokenApprove(address spender, uint256 amount) external;
}
