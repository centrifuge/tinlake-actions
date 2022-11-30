pragma solidity ^0.8.0;

// Tinlake Pool Interfaces

interface RootLike {
    function borrowerDeployer() external view returns (address);
    function lenderDeployer() external view returns (address);
}

interface BorrowerDeployerLike {
    function currency() external view returns (address);
    function shelf() external view returns (address);
    function pile() external view returns (address);
}
