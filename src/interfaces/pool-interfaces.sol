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
    function feed() external view returns (address);
}

interface LenderDeployerLike {
    function seniorOperator() external returns (address);
    function juniorOperator() external returns (address);
    function seniorMemberlist() external returns (address);
    function juniorMemberlist() external returns (address);
    function seniorTranche() external returns (address);
    function juniorTranche() external returns (address);
    function coordinator() external view returns (address);
    function assessor() external view returns (address);
    function reserve() external view returns (address);
}

interface ERC721Like {
    function approve(address usr, uint256 token) external;
    function transferFrom(address src, address dst, uint256 token) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface FeedLike {
    function file(bytes32 name, uint256 risk_, uint256 thresholdRatio_, uint256 ceilingRatio_, uint256 rate) external;
    function update(bytes32 name, uint256 value, uint256 riskGroup) external;
}

interface OperatorLike {
    function supplyOrder(uint256 supplyAmount) external;
}

interface MemberlistLike {
    function updateMember(address usr, uint256 validUntil) external;
}

interface ERC20Like {
    function approve(address usr, uint256 amount) external;
    function transfer(address dst, uint256 amount) external;
    function transferFrom(address src, address dst, uint256 amount) external;
    function mint(address usr, uint256 amount) external;
    function balanceOf(address usr) external view returns (uint256);
}

interface CoordinatorLike {
    function closeEpoch() external;
}

interface DependLike {
    function depend(bytes32 name, address addr) external;
}
