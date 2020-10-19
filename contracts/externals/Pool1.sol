pragma solidity ^0.5.0;

interface IPool1  {
    function changeDependentContractAddress() external;
    function makeCoverBegin(
        address smartCAdd,
        bytes4 coverCurr,
        uint[] calldata coverDetails,
        uint16 coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        external
        payable;
    function makeCoverUsingCA(
        address smartCAdd,
        bytes4 coverCurr,
        uint[] calldata coverDetails,
        uint16 coverPeriod,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        external;
    function getWei(uint amount) external view returns(uint);
    function sellNXMTokens(uint _amount) external  returns (bool);
}

