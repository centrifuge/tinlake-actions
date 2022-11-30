pragma solidity ^0.8.0;

// Tinlake Pool Interfaces

interface IRoot {
    function borrowerDeployer() external view returns (address);
}