// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.21;

import {Proxy, ProxyRegistry} from "tinlake-proxy/proxy.sol";
import {AssetNFT} from "tinlake-asset-nft/assetNFT.sol";
import {AssetMinter} from "tinlake-asset-nft/assetMinter.sol";
import {Actions} from "../src/actions.sol";
import "forge-std/Script.sol";

// Script to deploy Actions and Proxy contracts for NS2
contract NS2Spell is Script {
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

    function run() public {
        vm.startBroadcast();
        Actions actions = new Actions(NS2Root, NS2Borrower);
        address actions_ = address(actions);
        address proxy_ = proxyRegistry.build(NS2Borrower, actions_);
        Proxy proxy = Proxy(proxy_);
        vm.stopBroadcast();
    }
}
