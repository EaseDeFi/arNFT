pragma solidity ^0.5.0;

interface DSValue {
    function peek() external view returns (bytes32, bool);
    function read() external view returns (bytes32);
}

