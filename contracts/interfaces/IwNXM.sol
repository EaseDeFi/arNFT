pragma solidity 0.5.17;

interface wNXM{

    function _transfer(address sender, address recipient, uint256 amount) internal notwNXM(recipient);

    function wrap(uint256 _amount) external;

    function unwrap(uint256 _amount) external;

    function unwrapTo(address _to, uint256 _amount) public notwNXM(_to);

    function canWrap(address _owner, uint256 _amount) external view returns (bool success, string memory reason);

    function canUnwrap(address _owner, address _recipient, uint256 _amount) external view returns (bool success, string memory reason);

    /// @dev Method to claim junk and accidentally sent tokens
    function claimTokens(ERC20 _token, address payable _to, uint256 _balance) external;
}