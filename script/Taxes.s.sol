// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {Tax} from "../src/Tax.sol";

import {Constants} from "./base/Constants.sol";

/// @notice Creates a pool with Tax Hook using USDC and ZSTRAT tokens on Base and sets the tax recipient
contract SetTaxRecipient is Script, Constants {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    address constant TAX_HOOK = 0x8F79b9131d74b32642868fB4593DA678029180CC; // Deployed Tax Hook

    // New recipient address for tax collection
    address newRecipient = 0xe28d3Ec40f6C039c088f95C60bf50EaF7C327186; // Example recipient address

    function setUp() public {}

    function run() external {
        setUp();

        vm.startBroadcast(deployerPrivateKey);

        // Set tax recipient after pool creation
        console2.log("Setting tax recipient...");
        Tax(TAX_HOOK).setRecipient(newRecipient);
        console2.log("Tax recipient updated to:", newRecipient);

        vm.stopBroadcast();
    }
}
