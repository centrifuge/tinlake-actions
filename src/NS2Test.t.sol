pragma solidity ^0.8.1;
pragma experimental ABIEncoderV2;

import {Proxy, ProxyRegistry} from "tinlake-proxy/proxy.sol";
import {AssetNFT} from "tinlake-asset-nft/assetNFT.sol";
import {AssetMinter} from "tinlake-asset-nft/assetMinter.sol";
import {Actions} from "./actions.sol";
import {BasicPoolTest, OperatorLike, MemberlistLike, AuthLike} from "./basic-pool-test.sol";
import "forge-std/Test.sol";

contract ActionsTest is Test {
    address NS2Root;
    address NS2Borrower;
    ProxyRegistry proxyRegistry;
    AssetNFT assetNFT;
    AssetMinter minter;

    function setUp() public {
        NS2Root = address(0x53b2d22d07E069a3b132BfeaaD275b10273d381E);
        NS2Borrower = address(0x7Cae9bD865610750a48575aF15CAFe1e460c96a8);
        proxyRegistry = ProxyRegistry(address(0x4dbcF4322833B36e2E49a2d4dDcc7310074FdfEC));
        assetNFT = AssetNFT(address(0xA1829901090ff9364881EE75d008e5EA7e0e031A));
        minter = AssetMinter(address(0x8D25184fe134057c9d59e898bEb81AcD6519FEB3));
    }

    function testDeploy() public {
        Actions actions = new Actions(NS2Root, NS2Borrower);
        address actions_ = address(actions);
        address proxy = proxyRegistry.build(NS2Borrower, actions_);
        vm.startPrank(NS2Borrower);
        _issueNFT(NS2Borrower);
        vm.stopPrank();
    }

    function _issueNFT(address usr) public returns (uint256 tokenId, bytes32 nftID) {
        tokenId = assetNFT.mintTo(usr);
        nftID = keccak256(abi.encodePacked(address(assetNFT), tokenId));
    }
}