pragma solidity ^0.5.3;

import { Proxy, ProxyRegistry } from "tinlake-proxy/proxy.sol";
import { BaseSystemTest } from "tinlake/test/system/base_system.sol";
import { AdminUser } from "tinlake/test/system/users/admin.sol";
import "./actions.sol";

contract Hevm {
    function warp(uint256) public;
}

contract ActionsTest is BaseSystemTest {
    address       actions;
    address       self;
    ProxyRegistry registry;

    Proxy borrowerProxy;
    Proxy lenderProxy;
    address borrowerProxy_;
    address lenderProxy_;

    Proxy randomUserProxy;
    address randomUserProxy_ ;

    Hevm public hevm; 

    function setUp() public {
        bool seniorTranche = false;
        baseSetup();
        actions = address(new Actions());
        registry = new ProxyRegistry();
        self = address(this);

        admin = new AdminUser(address(shelf), address(pile), address(nftFeed), address(title), address(reserve), address(collector), address (juniorMemberlist), address (seniorMemberlist));
        admin_ = address(admin);
        root.relyBorrowerAdmin(admin_);

        borrowerProxy = Proxy(registry.build());
        borrowerProxy_ = address(borrowerProxy);
        borrower_ = address(this);
        lenderProxy = Proxy(registry.build());
        lenderProxy_ = address(lenderProxy);

        randomUserProxy     = Proxy(registry.build());
        randomUserProxy_   = address(randomUserProxy);

        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(1234567);
    }

    // ----- Lender -----
    function invest(uint amount) public {
        currency.mint(lenderProxy_, amount);
        lenderProxy.execute(actions, abi.encodeWithSignature("approveERC20(address,address,uint256)", address(currency), address(lenderDeployer.juniorTranche()), uint(-1)));
        address operator_ = address(lenderDeployer.juniorOperator());
        OperatorLike(operator_).relyInvestor(lenderProxy_);
        lenderProxy.execute(actions, abi.encodeWithSignature("supply(address,uint256)", operator_, amount));
    }

    // ----- Borrower -----
    function issue(uint tokenId) public returns(uint) {
         assertEq(collateralNFT.ownerOf(tokenId), borrower_);
        // approve nft transfer to proxy 
        collateralNFT.approve(borrowerProxy_, tokenId);
        bytes memory data = abi.encodeWithSignature("transferIssue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId);
        bytes memory response = borrowerProxy.execute(actions, data);
        (uint loan) = abi.decode(response, (uint));
        // assert: nft transferred to borrowerProxy
        assertEq(collateralNFT.ownerOf(tokenId), borrowerProxy_);
        // assert: loan created and owner is borrowerProxy
        assertEq(title.ownerOf(loan), borrowerProxy_);
        return loan;
    }

    function testIssueLockBorrow() public {
        // Borrower: Issue Loan
        (uint tokenId, ) = issueNFT(borrower_);
        uint loan = issue(tokenId);
        uint price = 50;
        uint riskGroup = 2;

        // Lender: lend
        uint amount = 100 ether;
        invest(amount);

        // Admin: set loan parameters
        setupLoan(tokenId, address(collateralNFT), price, riskGroup);

        // Borrower: Lock & Borrow
        borrowerProxy.execute(actions, abi.encodeWithSignature("lockBorrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, borrower_));
        assertEq(collateralNFT.ownerOf(1), address(shelf));
        // check if borrower received loan amount
        assertEq(currency.balanceOf(borrower_), amount);
    }

    function testFailIssueLockBorrowerWithdrawCeilingNotSet() public {
        (uint tokenId, ) = issueNFT(borrower_);
        uint amount = 100 ether;
        borrowerProxy.execute(actions, abi.encodeWithSignature("issueLockBorrowWithdraw(address,address,uint256,uint256,address)", address(shelf), address(collateralNFT), tokenId, amount, borrower_));
    }

    function testFailIssueBorrowerNotOwner() public {
        uint tokenId = collateralNFT.issue(randomUserProxy_);
        bytes memory data = abi.encodeWithSignature("issue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId);
        // randomProxy not owner of nft
        borrowerProxy.execute(actions, data);
    }

    function testFailBorrowNotLoanOwner() public {
        (uint tokenId, ) = issueNFT(borrower_);
        bytes memory data = abi.encodeWithSignature("issue(address,address,uint256)", address(shelf), address(collateralNFT), tokenId);
        bytes memory response = borrowerProxy.execute(actions, data);
        (uint loan) = abi.decode(response, (uint));
        borrowerProxy.execute(actions, abi.encodeWithSignature("lock(address,uint256)", address(shelf), loan));

        // Lend:
        uint amount = 100 ether;
        invest(amount);

        // Admin: set loan parameters
        uint price = 50;
        uint riskGroup = 2;
        setupLoan(tokenId, address(collateralNFT), price, riskGroup);

        // RandomUserProxy: Borrow & Withdraw
        randomUserProxy.execute(actions, abi.encodeWithSignature("borrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, randomUserProxy_));
    }

    function testRepayUnlockClose() public {
        // Borrower: Issue Loan
        (uint tokenId, bytes32 lookupId) = issueNFT(borrower_);
        uint loan = issue(tokenId);

        // Lender: lend
        uint amount = 100 ether;
        invest(amount);
        
        // Admin: set loan parameters
        uint price = 50;
        uint riskGroup = 2;
        setupLoan(tokenId, address(collateralNFT), price, riskGroup);

        // Borrower: Lock & Borrow
        borrowerProxy.execute(actions, abi.encodeWithSignature("lockBorrowWithdraw(address,uint256,uint256,address)", address(shelf), loan, amount, borrower_));
       
        // accrue interest
        hevm.warp(now + 365 days);

        // mint currency for borrower to cover interest 
        currency.mint(borrower_, 15 ether);
        // allow proxy to take money for repayment
        currency.approve(borrowerProxy_, 115 ether);
        // Borrower: Repay & Unlock & Close
        borrowerProxy.execute(actions, abi.encodeWithSignature("repayUnlockClose(address,address,address,uint256,address,uint256)", address(shelf), address(pile), address(collateralNFT), tokenId, address(currency), loan));
        // assert: nft transfered back to borrower
        assertEq(collateralNFT.ownerOf(tokenId), address(borrower_));
        assertEq(shelf.nftlookup(lookupId), 0);
    }

    // --- Lender ---
    function testFailSupplyNotWhitelisted() public {
        // Lend:
        uint investment = 100 ether;
        currency.mint(lenderProxy_, investment);
        lenderProxy.execute(actions, abi.encodeWithSignature("approveERC20(address,address,uint256)", address(currency), address(lenderDeployer.juniorTranche()), uint(-1)));
        lenderProxy.execute(actions, abi.encodeWithSignature("supply(address,uint256)", address(juniorOperator), investment));
    }
}
