pragma solidity ^0.5.0;

import "./IERC721.sol";

contract IERC721Enumerable is IERC721 {
    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256 tokenId);
}
