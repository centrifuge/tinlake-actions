pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {Proxy, ProxyRegistry} from "tinlake-proxy/proxy.sol";
import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {Actions, PileLike, ShelfLike, ERC20Like } from "./actions.sol";
import {RootLike, BorrowerDeployerLike, ERC721Like} from "./interfaces/pool-interfaces.sol";
import {Test} from "forge-std/Test.sol";
import {DSTest} from "ds-test/test.sol";

import "./actions.sol";

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
    address public borrowerProxy_;
    ProxyRegistry public registry;

    Collateral public collateralNFT;

    // Pool Interfaces

    // BT Pool on Mainnet for testing
    address public rootContract = 0x4597f91cC06687Bdb74147C80C097A79358Ed29b;

    // DAI
    ERC20Like public currency;
    PileLike public pile;
    ShelfLike public shelf;

    ERC721Like public title;

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
        BorrowerDeployerLike borrowerDeployer = BorrowerDeployerLike(root.borrowerDeployer());

        currency = ERC20Like(borrowerDeployer.currency());

        // get super powers on DAI contract
        vm.store(address(currency), keccak256(abi.encode(address(this), uint256(0))), bytes32(uint256(1)));

        pile = PileLike(borrowerDeployer.pile());
        shelf = ShelfLike(borrowerDeployer.shelf());
        title = ERC721Like(borrowerDeployer.title());
    }

    function setUp() public {
        // get pool addresses from root contract
        _setUpPoolInterfaces();
        collateralNFT = new Collateral();


        // test contract is borrower
        borrower_ = address(this);

        // get proxy
        actions = address(new Actions());
        registry = new ProxyRegistry();

        borrowerProxy = Proxy(registry.build());
        borrowerProxy.addUser(borrower_);

        borrowerProxy.file("target", address(actions));

        borrowerProxy_ = address(borrowerProxy);

    }

    function _issueNFT(address usr) public returns (uint256 tokenId, bytes32 nftID) {
        tokenId = collateralNFT.mint(usr);
        nftID = keccak256(abi.encodePacked(address(collateralNFT), tokenId));
    }

    function testBasic() public {}

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
        //    uint price = 50;
        //    uint amount = 25;
        //    uint riskGroup = 2;

        //    // Lender: lend
        //    defaultInvest(100 ether);
        //    hevm.warp(block.timestamp + 1 days);
        //    coordinator.closeEpoch();

        //    // Admin: set loan parameters
        //    priceNFTandSetRisk(tokenId, price, riskGroup);

        //    // Borrower: Lock & Borrow
        //    borrowerProxy.execute(actions, abi.encodeWithSignature("lockBorrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, borrower_));
        //    assertEq(collateralNFT.ownerOf(1), address(shelf));
        //    // check if borrower received loan amount
        //    assertEq(currency.balanceOf(borrower_), amount);
    }

    //     function testFailIssueLockBorrowerWithdrawCeilingNotSet() public {
    //         (uint tokenId, ) = issueNFT(borrower_);
    //         uint amount = 100 ether;
    //         borrowerProxy.execute(actions, abi.encodeWithSignature("issueLockBorrowWithdraw(address,address,uint256,uint256,address)", address(shelf), address(collateralNFT), tokenId, amount, borrower_));
    //     }

    //     function testFailIssueBorrowerNotOwner() public {
    //         uint tokenId = collateralNFT.issue(randomUserProxy_);
    //         bytes memory data = abi.encodeWithSignature("issue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId);
    //         // randomProxy not owner of nft
    //         borrowerProxy.execute(actions, data);
    //     }

    //     function testFailBorrowNotLoanOwner() public {
    //         (uint tokenId, ) = issueNFT(borrower_);
    //         bytes memory data = abi.encodeWithSignature("issue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId);
    //         bytes memory response = borrowerProxy.execute(actions, data);
    //         (uint loan) = abi.decode(response, (uint));
    //         borrowerProxy.execute(actions, abi.encodeWithSignature("lock(address,uint256)", address(shelf), loan));

    //         // Lend:
    //         uint amount = 100 ether;
    //         fundLender(amount);

    //         // Admin: set loan parameters
    //         uint price = 50;
    //         uint riskGroup = 2;
    //         setupLoan(tokenId, address(collateralNFT), price, riskGroup);

    //         // RandomUserProxy: Borrow & Withdraw
    //         randomUserProxy.execute(actions, abi.encodeWithSignature("borrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, randomUserProxy_));
    //     }

    //    function testRepayUnlockClose() public {
    //        // Borrower: Issue Loan
    //        (uint tokenId, bytes32 lookupId) = issueNFT(borrower_);
    //        uint loan = issue(tokenId);

    //        // Lender: lend
    //        defaultInvest(100 ether);
    //        hevm.warp(block.timestamp + 1 days);
    //        coordinator.closeEpoch();

    //        // Admin: set loan parameters
    //        uint price = 50;
    //        uint riskGroup = 2;
    //        uint amount = 25;
    //        priceNFTandSetRisk(tokenId, price, riskGroup);

    //        // Borrower: Lock & Borrow
    //        borrowerProxy.execute(actions, abi.encodeWithSignature("lockBorrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, borrower_));

    //        // accrue interest
    //        hevm.warp(block.timestamp + 365 days);

    //        // mint currency for borrower to cover interest
    //        currency.mint(borrower_, 15 ether);
    //        // allow proxy to take money for repayment
    //        currency.approve(borrowerProxy_, 115 ether);
    //        // Borrower: Repay & Unlock & Close
    //        borrowerProxy.execute(actions, abi.encodeWithSignature("repayUnlockClose(address,address,address,uint256,address,uint256)", address(shelf), address(pile), address(collateralNFT), tokenId, address(currency), loan));
    //        // assert: nft transfered back to borrower
    //        assertEq(collateralNFT.ownerOf(tokenId), address(borrower_));
    //        assertEq(shelf.nftlookup(lookupId), 0);
    //    }
}
