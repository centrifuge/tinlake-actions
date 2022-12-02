pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {Proxy, ProxyRegistry} from "tinlake-proxy/proxy.sol";
import {AssetNFT} from "tinlake-asset-nft/assetNFT.sol";
import {Actions} from "./actions.sol";
import {BasisPoolTest, OperatorLike, MemberlistLike, AuthLike} from "./basic-pool-test.sol";

contract ActionsTest is BasisPoolTest {
    Actions public bActions;
    Actions public randomUserActions;
    Proxy public borrowerProxy;
    Proxy public randomUserProxy;
    address public borrowerProxy_;
    ProxyRegistry public registry;
    AssetNFT public collateralNFT;

    address randomUserProxy_ = address(0x123);
    address internal borrower_;
    address internal withdrawAddress_;

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
        collateralNFT = new AssetNFT();

        // test contract is borrower
        borrower_ = address(this);
        withdrawAddress_ = address(this);

        registry = new ProxyRegistry();

        (borrowerProxy, bActions) = _createProxyAndActions(rootContract, withdrawAddress_);

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
        tokenId = collateralNFT.mintTo(usr);
        nftID = keccak256(abi.encodePacked(address(collateralNFT), tokenId));
    }

    function _invest(uint256 amount) public {
        defaultInvest(amount);
        vm.warp(block.timestamp + 1 days);
        coordinator.closeEpoch();
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

    function _issueLockBorrow(Actions actions) internal returns (uint256, uint256) {
        // Borrower: Issue Loan
        (uint256 tokenId,) = _issueNFT(borrower_);
        uint256 loan = issue(tokenId);
        uint256 price = 100;
        uint256 amount = 25;
        uint256 riskGroup = 0;

        // Lender: lend
        _invest(100 ether);

        // Admin: set loan parameters
        priceNFTandSetRisk(tokenId, price, riskGroup);

        // Borrower: Lock & Borrow
        borrowerProxy.userExecute(
            address(actions), abi.encodeWithSignature("lockBorrowWithdraw(uint256,uint256)", loan, amount)
        );
        assertEq(collateralNFT.ownerOf(tokenId), address(shelf));
        // check if borrower received loan amount
        assertEq(currency.balanceOf(borrower_), amount);
        return (loan, amount);
    }

    function testMint() public {
        // proxy allowed to mint
        collateralNFT.rely(borrowerProxy_);

        bytes memory response = borrowerProxy.userExecute(
            address(bActions), abi.encodeWithSignature("mintAsset(address)", address(collateralNFT))
        );
        (uint256 tokenId) = abi.decode(response, (uint256));
        assertEq(collateralNFT.ownerOf(tokenId), borrowerProxy_);
        assertEq(tokenId, 1);
    }

    function testMintIssuePriceLock() public returns (uint256 loan, uint256 tokenId) {
        // proxy allowed to mint
        collateralNFT.rely(borrowerProxy_);

        // proxy allowed to update feed
        vm.startPrank(address(rootContract));
        AuthLike(address(feed)).rely(borrowerProxy_);
        vm.stopPrank();

        uint256 price = 100 ether;
        uint256 riskGroup = 0;

        bytes memory response = borrowerProxy.userExecute(
            address(bActions),
            abi.encodeWithSignature(
                "mintIssuePriceLock(address,uint256,uint256)", address(collateralNFT), price, riskGroup
            )
        );
        (loan, tokenId) = abi.decode(response, (uint256, uint256));
        assertEq(collateralNFT.ownerOf(tokenId), address(shelf));
        assertEq(title.ownerOf(loan), borrowerProxy_);
    }

    function testFullBorrowFlow() public {
        _invest(100 ether);

        (uint256 loan,) = testMintIssuePriceLock();
        uint256 amount = 25 ether;
        uint256 secondAmount = 2 ether;
        borrowerProxy.userExecute(
            address(bActions), abi.encodeWithSignature("borrowWithdraw(uint256,uint256)", loan, amount)
        );
        borrowerProxy.userExecute(
            address(bActions), abi.encodeWithSignature("borrowWithdraw(uint256,uint256)", loan, secondAmount)
        );
        assertEq(currency.balanceOf(withdrawAddress_), amount + secondAmount);
    }

    function testIssueLockBorrow() public {
        _issueLockBorrow(bActions);
    }

    function testFailWrongActionContract() public {
        _issueLockBorrow(randomUserActions);
    }

    function testBorrowWithdrawMultipleTimes() public {
        (uint256 loan, uint256 amount) = _issueLockBorrow(bActions);
        uint256 secondAmount = 12;
        borrowerProxy.userExecute(
            address(bActions), abi.encodeWithSignature("borrowWithdraw(uint256,uint256)", loan, secondAmount)
        );

        assertEq(currency.balanceOf(borrower_), amount + secondAmount);
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
