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
    function title() external view returns (address);
}

interface ERC721Like {
    function approve(address usr, uint256 token) external;
    function transferFrom(address src, address dst, uint256 token) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}
