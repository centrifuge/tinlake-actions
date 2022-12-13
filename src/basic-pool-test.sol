pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {
    RootLike,
    BorrowerDeployerLike,
    LenderDeployerLike,
    ERC721Like,
    FeedLike,
    OperatorLike,
    MemberlistLike,
    ERC20Like,
    CoordinatorLike,
    DependLike,
    ShelfLike,
    PileLike
} from "./interfaces/pool-interfaces.sol";

import {Test} from "forge-std/Test.sol";

contract BasisPoolTest is Test {
    uint256 public constant ONE = 10 ** 27;

    // Pool Interfaces

    // BT Pool on Mainnet for testing
    address public rootContract;

    // DAI
    ERC20Like public currency;
    PileLike public pile;
    ShelfLike public shelf;
    FeedLike public feed;
    CoordinatorLike public coordinator;

    ERC721Like public title;
    LenderDeployerLike public lenderDeployer;
    BorrowerDeployerLike public borrowerDeployer;

    function _checkRoot() internal view {
        uint32 size;
        address _addr = rootContract;
        assembly {
            size := extcodesize(_addr)
        }
        require(size > 0, "test-suite: no contract found on testnet/mainnet");
    }

    function _setUpPoolInterfaces() internal {
        _checkRoot();
        RootLike root = RootLike(rootContract);
        borrowerDeployer = BorrowerDeployerLike(root.borrowerDeployer());
        lenderDeployer = LenderDeployerLike(root.lenderDeployer());

        currency = ERC20Like(borrowerDeployer.currency());

        // get super powers on DAI contract
        vm.store(address(currency), keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));

        pile = PileLike(borrowerDeployer.pile());
        shelf = ShelfLike(borrowerDeployer.shelf());
        title = ERC721Like(borrowerDeployer.title());
        feed = FeedLike(borrowerDeployer.feed());
        coordinator = CoordinatorLike(lenderDeployer.coordinator());

        // deactivate Maker
        vm.startPrank(address(rootContract));
        DependLike(lenderDeployer.assessor()).depend("lending", address(0));
        DependLike(lenderDeployer.reserve()).depend("lending", address(0));
        vm.stopPrank();
    }

    function _fileRiskGroup() internal {
        vm.startPrank(address(rootContract));
        feed.file(
            "riskGroup",
            0, // riskGroup:       0
            8 * 10 ** 26, // thresholdRatio   70%
            6 * 10 ** 26, // ceilingRatio     60%
            uint256(1000000564701133626865910626) // interestRate     5% per year
        );
        vm.stopPrank();
    }
}
