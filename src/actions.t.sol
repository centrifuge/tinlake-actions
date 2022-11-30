pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {Proxy, ProxyRegistry} from "tinlake-proxy/proxy.sol";
import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {Actions, PileLike} from "./actions.sol";
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
    ShelfLike
} from "./interfaces/pool-interfaces.sol";
import {Test} from "forge-std/Test.sol";
import {DSTest} from "ds-test/test.sol";

contract Collateral is ERC721("Collateral", "COL") {
    uint256 public nextTokenId;

    function mint(address usr) public returns (uint256) {
        uint256 id = nextTokenId;
        _mint(usr, nextTokenId);
        nextTokenId++;
        return id;
    }
}

contract ActionsTest is Test {
    address public actions;
    Proxy public borrowerProxy;
    Proxy public randomUserProxy;
    address public borrowerProxy_;
    ProxyRegistry public registry;

    Collateral public collateralNFT;

    uint256 public constant ONE = 10 ** 27;

    // Pool Interfaces

    // BT Pool on Mainnet for testing
    address public rootContract = 0x4597f91cC06687Bdb74147C80C097A79358Ed29b;

    // DAI
    ERC20Like public currency;
    PileLike public pile;
    ShelfLike public shelf;
    FeedLike public feed;
    CoordinatorLike public coordinator;

    ERC721Like public title;
    LenderDeployerLike public lenderDeployer;
    BorrowerDeployerLike public borrowerDeployer;
    address randomUserProxy_ = address(0x123);

    address internal borrower_;

    function _checkRoot() internal {
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

    function setUp() public {
        // get pool addresses from root contract
        _setUpPoolInterfaces();
        _fileRiskGroup();
        collateralNFT = new Collateral();

        // test contract is borrower
        borrower_ = address(this);

        // get proxy
        actions = address(new Actions());
        registry = new ProxyRegistry();

        borrowerProxy = Proxy(registry.build());
        borrowerProxy.addUser(borrower_);
        borrowerProxy.file("target", address(actions));

        randomUserProxy = Proxy(registry.build());
        randomUserProxy.addUser(address(0x123));
        randomUserProxy.file("target", address(actions));

        borrowerProxy_ = address(borrowerProxy);
    }

    function priceNFTandSetRisk(uint256 tokenId, uint256 value, uint256 riskGroup) public {
        bytes32 lookupId = keccak256(abi.encodePacked(address(collateralNFT), tokenId));

        vm.startPrank(address(rootContract));
        feed.update(lookupId, value, riskGroup);
        vm.stopPrank();
    }

    function _issueNFT(address usr) public returns (uint256 tokenId, bytes32 nftID) {
        tokenId = collateralNFT.mint(usr);
        nftID = keccak256(abi.encodePacked(address(collateralNFT), tokenId));
    }

    function testBasic() public {
        _checkRoot();
    }

    function defaultInvest(uint256 currencyAmount) public {
        vm.startPrank(address(rootContract));
        uint256 validUntil = block.timestamp + 8 days;

        MemberlistLike(lenderDeployer.seniorMemberlist()).updateMember(borrower_, validUntil);
        MemberlistLike(lenderDeployer.juniorMemberlist()).updateMember(borrower_, validUntil);
        vm.stopPrank();

        // 80% from senior
        uint256 amountSenior = (currencyAmount * (ONE * 7) / 10) / ONE;
        // 20% from junior
        uint256 amountJunior = (currencyAmount * (ONE * 3) / 10) / ONE;

        currency.mint(borrower_, amountSenior + amountJunior);

        // approve currency transfer
        currency.approve(lenderDeployer.seniorTranche(), amountSenior);
        currency.approve(lenderDeployer.juniorTranche(), amountJunior);
        OperatorLike(lenderDeployer.seniorOperator()).supplyOrder(amountSenior);
        OperatorLike(lenderDeployer.juniorOperator()).supplyOrder(amountJunior);
    }

    // ----- Borrower -----
    function issue(uint256 tokenId) public returns (uint256) {
        assertEq(collateralNFT.ownerOf(tokenId), borrower_);
        // approve nft transfer to proxy
        collateralNFT.approve(borrowerProxy_, tokenId);
        bytes memory data = abi.encodeWithSignature(
            "transferIssue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId
        );
        bytes memory response = borrowerProxy.userExecute(actions, data);
        (uint256 loan) = abi.decode(response, (uint256));
        // assert: nft transferred to borrowerProxy
        assertEq(collateralNFT.ownerOf(tokenId), borrowerProxy_);
        // assert: loan created and owner is borrowerProxy
        assertEq(title.ownerOf(loan), borrowerProxy_);
        return loan;
    }

    function testIssueLockBorrow() public {
        // Borrower: Issue Loan
        (uint256 tokenId,) = _issueNFT(borrower_);
        uint256 loan = issue(tokenId);
        uint256 price = 50;
        uint256 amount = 25;
        uint256 riskGroup = 0;

        // Lender: lend
        defaultInvest(100 ether);
        vm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();

        // Admin: set loan parameters
        priceNFTandSetRisk(tokenId, price, riskGroup);

        // Borrower: Lock & Borrow
        borrowerProxy.userExecute(
            actions,
            abi.encodeWithSignature(
                "lockBorrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, borrower_
            )
        );
        assertEq(collateralNFT.ownerOf(tokenId), address(shelf));
        // check if borrower received loan amount
        assertEq(currency.balanceOf(borrower_), amount);
    }

    function testFailIssueLockBorrowerWithdrawCeilingNotSet() public {
        (uint256 tokenId,) = _issueNFT(borrower_);
        uint256 amount = 100 ether;
        borrowerProxy.userExecute(
            actions,
            abi.encodeWithSignature(
                "issueLockBorrowWithdraw(address,address,uint256,uint256,address)",
                address(shelf),
                address(collateralNFT),
                tokenId,
                amount,
                borrower_
            )
        );
    }

    function testFailIssueBorrowerNotOwner() public {
        (uint256 tokenId,) = _issueNFT(randomUserProxy_);
        bytes memory data =
            abi.encodeWithSignature("issue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId);
        // randomProxy not owner of nft
        borrowerProxy.userExecute(actions, data);
    }

    function testFailBorrowNotLoanOwner() public {
        (uint256 tokenId,) = _issueNFT(borrower_);
        bytes memory data =
            abi.encodeWithSignature("issue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId);
        bytes memory response = borrowerProxy.userExecute(actions, data);
        (uint256 loan) = abi.decode(response, (uint256));
        borrowerProxy.userExecute(actions, abi.encodeWithSignature("lock(address,uint256)", address(shelf), loan));

        // Lend:
        uint256 amount = 100 ether;
        defaultInvest(amount);

        // Admin: set loan parameters
        uint256 price = 50;
        uint256 riskGroup = 0;

        // price collateral and add to riskgroup
        priceNFTandSetRisk(tokenId, price, riskGroup);

        // RandomUserProxy: Borrow & Withdraw
        randomUserProxy.userExecute(
            actions,
            abi.encodeWithSignature(
                "borrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, randomUserProxy_
            )
        );
    }

    function testRepayUnlockClose() public {
        // Borrower: Issue Loan
        (uint256 tokenId, bytes32 lookupId) = _issueNFT(borrower_);
        uint256 loan = issue(tokenId);

        // Lender: lend
        defaultInvest(100 ether);
        vm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();

        // Admin: set loan parameters
        uint256 price = 50;
        uint256 riskGroup = 0;
        uint256 amount = 25;
        priceNFTandSetRisk(tokenId, price, riskGroup);

        // Borrower: Lock & Borrow
        borrowerProxy.userExecute(
            actions,
            abi.encodeWithSignature(
                "lockBorrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, borrower_
            )
        );

        // accrue interest
        vm.warp(block.timestamp + 365 days);

        // mint currency for borrower to cover interest
        currency.mint(borrower_, 15 ether);
        // allow proxy to take money for repayment
        currency.approve(borrowerProxy_, 115 ether);
        // Borrower: Repay & Unlock & Close
        borrowerProxy.userExecute(
            actions,
            abi.encodeWithSignature(
                "repayUnlockClose(address,address,address,uint256,address,uint256)",
                address(shelf),
                address(pile),
                address(collateralNFT),
                tokenId,
                address(currency),
                loan
            )
        );
        // assert: nft transfered back to borrower
        assertEq(collateralNFT.ownerOf(tokenId), address(borrower_));
        assertEq(shelf.nftlookup(lookupId), 0);
    }
}
