pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {Proxy, ProxyRegistry} from "tinlake-proxy/proxy.sol";
import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import {Actions} from "./actions.sol";
import {BasisPoolTest, OperatorLike, MemberlistLike} from "./basic-pool-test.sol";

contract Collateral is ERC721("Collateral", "COL") {
    uint256 public nextTokenId;

    function mint(address usr) public returns (uint256) {
        uint256 id = nextTokenId;
        _mint(usr, nextTokenId);
        nextTokenId++;
        return id;
    }
}

contract ActionsTest is BasisPoolTest {
    Actions public bActions;
    Actions public randomUserActions;
    Proxy public borrowerProxy;
    Proxy public randomUserProxy;
    address public borrowerProxy_;
    ProxyRegistry public registry;
    Collateral public collateralNFT;

    address randomUserProxy_ = address(0x123);
    address internal borrower_;

    function _createProxyAndActions(address root, address proxyUser) internal returns (Proxy proxy, Actions actions) {
        proxy = Proxy(registry.build());
        proxy.addUser(proxyUser);
        actions = new Actions(root, proxyUser);
        proxy.file("target", address(actions));
    }

    function setUp() public {
        // default BT 1 mainnet pool
        rootContract = 0x4597f91cC06687Bdb74147C80C097A79358Ed29b;
        // get pool addresses from root contract
        _setUpPoolInterfaces();
        _fileRiskGroup();
        collateralNFT = new Collateral();

        // test contract is borrower
        borrower_ = address(this);

        registry = new ProxyRegistry();

        (borrowerProxy, bActions) = _createProxyAndActions(rootContract, borrower_);

        borrowerProxy_ = address(borrowerProxy);
        (randomUserProxy, randomUserActions) = _createProxyAndActions(rootContract, randomUserProxy_);
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

    function testBasic() public view {
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
        bytes memory data = abi.encodeWithSignature("transferIssue(address,uint256)", address(collateralNFT), tokenId);
        bytes memory response = borrowerProxy.userExecute(address(bActions), data);
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
            address(bActions), abi.encodeWithSignature("lockBorrowWithdraw(uint256,uint256)", loan, amount)
        );
        assertEq(collateralNFT.ownerOf(tokenId), address(shelf));
        // check if borrower received loan amount
        assertEq(currency.balanceOf(borrower_), amount);
    }

    function testFailIssueLockBorrowerWithdrawCeilingNotSet() public {
        (uint256 tokenId,) = _issueNFT(borrower_);
        uint256 amount = 100 ether;
        borrowerProxy.userExecute(
            address(bActions),
            abi.encodeWithSignature(
                "issueLockBorrowWithdraw(address,uint256,uint256)", address(collateralNFT), tokenId, amount, borrower_
            )
        );
    }

    function testFailIssueBorrowerNotOwner() public {
        (uint256 tokenId,) = _issueNFT(randomUserProxy_);
        bytes memory data = abi.encodeWithSignature("issue(address,address,uint256)", address(collateralNFT), tokenId);
        // randomProxy not owner of nft
        borrowerProxy.userExecute(address(bActions), data);
    }

    function testFailBorrowNotLoanOwner() public {
        (uint256 tokenId,) = _issueNFT(borrower_);
        bytes memory data = abi.encodeWithSignature("issue(address,uint256)", address(collateralNFT), tokenId);
        bytes memory response = borrowerProxy.userExecute(address(bActions), data);
        (uint256 loan) = abi.decode(response, (uint256));
        borrowerProxy.userExecute(address(bActions), abi.encodeWithSignature("lock(uint256)", loan));

        // Lend:
        uint256 amount = 100 ether;
        defaultInvest(amount);

        // Admin: set loan parameters
        uint256 price = 50;
        uint256 riskGroup = 0;

        // price collateral and add to riskgroupaddress
        priceNFTandSetRisk(tokenId, price, riskGroup);

        // RandomUserProxy: Borrow & Withdraw
        randomUserProxy.userExecute(
            address(randomUserActions), abi.encodeWithSignature("borrowWithdraw(uint256,uint256)", loan, amount)
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
            address(bActions), abi.encodeWithSignature("lockBorrowWithdraw(uint256,uint256)", loan, amount)
        );

        // accrue interest
        vm.warp(block.timestamp + 365 days);

        // mint currency for borrower to cover interest
        currency.mint(borrower_, 15 ether);
        // allow proxy to take money for repayment
        currency.approve(borrowerProxy_, 115 ether);
        // Borrower: Repay & Unlock & Close
        borrowerProxy.userExecute(
            address(bActions),
            abi.encodeWithSignature(
                "repayUnlockClose(address,uint256,address,uint256)",
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
