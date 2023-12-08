pragma solidity ^0.8.1;
pragma experimental ABIEncoderV2;

import {Proxy, ProxyRegistry} from "tinlake-proxy/proxy.sol";
import {AssetNFT} from "tinlake-asset-nft/assetNFT.sol";
import {AssetMinter} from "tinlake-asset-nft/assetMinter.sol";
import {Actions} from "./actions.sol";
import {BasicPoolTest, OperatorLike, MemberlistLike, AuthLike} from "./basic-pool-test.sol";
import "forge-std/Test.sol";

interface NFTLike {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface RootLike {
    function relyContract(address target, address usr) external;
    function denyContract(address target, address usr) external;
}

interface ERC20Like {
    function approve(address usr, uint256 amount) external;
    function allowance(address usr, address spender) external view returns (uint256);
    function balanceOf(address usr) external view returns (uint256);
}

interface ShelfLike {
    function nftlookup(bytes32 lookupId) external view returns (uint256);
}

interface FeedLike {
    function maturityDate(bytes32 nftId) external view returns (uint256);
    function nftID(uint256 loan) external view returns (bytes32);
}

contract NS2Test is Test {
    address centrifugeMultisig;
    address NS2Root;
    address NS2Borrower;
    address NS2Shelf;
    address NS2Title;
    address NS2Feed;
    address NS2Pile;
    ProxyRegistry proxyRegistry;
    AssetNFT assetNFT;
    AssetMinter minter;
    Proxy proxy;

    function setUp() public {
        // shared contracts
        centrifugeMultisig = address(0xf3BceA7494D8f3ac21585CA4b0E52aa175c24C25);
        proxyRegistry = ProxyRegistry(address(0x4dbcF4322833B36e2E49a2d4dDcc7310074FdfEC));
        assetNFT = AssetNFT(address(0xA1829901090ff9364881EE75d008e5EA7e0e031A));
        minter = AssetMinter(address(0x8D25184fe134057c9d59e898bEb81AcD6519FEB3));
        // NS2 contracts
        NS2Root = address(0x53b2d22d07E069a3b132BfeaaD275b10273d381E);
        NS2Borrower = address(0x7Cae9bD865610750a48575aF15CAFe1e460c96a8);
        NS2Shelf = address(0x7d057A056939bb96D682336683C10EC89b78D7CE);
        NS2Title = address(0x07cdD617c53B07208b0371C93a02deB8d8D49C6e);
        NS2Feed = address(0x41fAD1Eb242De19dA0206B0468763333BB6C2B3D);
        NS2Pile = address(0x3eC5c16E7f2C6A80E31997C68D8Fa6ACe089807f);
    }

    function testMintBorrowRepay() public {
        Actions actions = new Actions(NS2Root, NS2Borrower);
        address actions_ = address(actions);
        address proxy_ = proxyRegistry.build(NS2Borrower, actions_);
        Proxy proxy = Proxy(proxy_);

        vm.startPrank(centrifugeMultisig);
        minter.rely(proxy_);
        RootLike(NS2Root).relyContract(NS2Feed, proxy_);
        vm.stopPrank();

        uint256 price = 100 ether;
        uint256 riskGroup = 0;
        uint256 loan;
        uint256 tokenId;

        vm.prank(NS2Borrower);
        bytes memory response = proxy.userExecute(
            address(actions),
            abi.encodeWithSignature(
                "mintIssuePriceLock(address,address,uint256,uint256,uint256)",
                address(minter),
                address(assetNFT),
                price,
                riskGroup,
                1733358595
            )
        );
        (loan, tokenId) = abi.decode(response, (uint256, uint256));
        assertEq(assetNFT.ownerOf(tokenId), address(NS2Shelf));
        assertEq(NFTLike(NS2Title).ownerOf(loan), proxy_);

        address DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        deal(DAI, NS2Borrower, 1_000_000_000 ether);
        assertEq(ERC20Like(DAI).balanceOf(NS2Borrower), 1_000_000_000 ether);

        vm.prank(NS2Borrower);
        ERC20Like(DAI).approve(proxy_, 100000000000 ether);
        assertEq(ERC20Like(DAI).allowance(NS2Borrower, proxy_), 100000000000 ether);

        bytes32 lookupId = keccak256(abi.encodePacked(address(assetNFT), tokenId));
        assertNotEq(ShelfLike(NS2Shelf).nftlookup(lookupId), 0);

        loan = 414;
        tokenId = uint256(3083736064639503361534905223767714443490692247707662060881607854475424729587);

        vm.prank(NS2Borrower);
        vm.expectRevert("TinlakeProxy/delegate-call-failed");
        proxy.userExecute(
            address(actions),
            abi.encodeWithSignature(
                "repayUnlockClose(address,address,address,uint256,address,uint256)",
                address(NS2Shelf),
                address(NS2Pile),
                address(assetNFT),
                tokenId,
                DAI,
                loan
            )
        );
    }

    function testMintWithMaturityDate() public {
        Actions actions = new Actions(NS2Root, NS2Borrower);
        address actions_ = address(actions);
        address proxy_ = proxyRegistry.build(NS2Borrower, actions_);
        Proxy proxy = Proxy(proxy_);

        vm.startPrank(centrifugeMultisig);
        minter.rely(proxy_);
        RootLike(NS2Root).relyContract(NS2Feed, proxy_);
        vm.stopPrank();

        uint256 price = 10 ether;
        uint256 riskGroup = 1;
        uint256 loan;
        uint256 tokenId;

        vm.prank(NS2Borrower);
        bytes memory response = proxy.userExecute(
            address(actions),
            abi.encodeWithSignature(
                "mintIssuePriceLock(address,address,uint256,uint256,uint256)",
                address(minter),
                address(assetNFT),
                price,
                riskGroup,
                1704585600
            )
        );
        (loan, tokenId) = abi.decode(response, (uint256, uint256));
        assertEq(assetNFT.ownerOf(tokenId), address(NS2Shelf));
        assertEq(NFTLike(NS2Title).ownerOf(loan), proxy_);
        bytes32 nftId = FeedLike(NS2Feed).nftID(loan);
        assertEq(FeedLike(NS2Feed).maturityDate(nftId), 1704585600);
    }

    function testSwappingActionsContractAndMint() public {
        Actions actions = new Actions(NS2Root, NS2Borrower);
        address actions_ = address(actions);
        address proxy_ = address(0x098498bDDF654cB416537c07889bF46E9f96a54b);
        Proxy proxy = Proxy(proxy_);

        vm.startPrank(centrifugeMultisig);
        proxy.file("target", actions_);
        minter.rely(proxy_);
        RootLike(NS2Root).relyContract(NS2Feed, proxy_);
        vm.stopPrank();

        uint256 price = 100 ether;
        uint256 riskGroup = 0;
        uint256 loan;
        uint256 tokenId;

        vm.prank(NS2Borrower);
        bytes memory response = proxy.userExecute(
            address(actions),
            abi.encodeWithSignature(
                "mintIssuePriceLock(address,address,uint256,uint256,uint256)",
                address(minter),
                address(assetNFT),
                price,
                riskGroup,
                1733358595
            )
        );
        (loan, tokenId) = abi.decode(response, (uint256, uint256));
        assertEq(assetNFT.ownerOf(tokenId), address(NS2Shelf));
        assertEq(NFTLike(NS2Title).ownerOf(loan), proxy_);
    }
}
