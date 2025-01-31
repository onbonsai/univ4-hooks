// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

import {DefaultSettings} from "../src/utils/DefaultSettings.sol";
import {DefaultHook} from "../src/DefaultHook.sol";

/// @notice Mines the address and deploys the Counter.sol Hook contract
contract CounterScript is Script, Constants {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {}

    function run() public {
        // deploy default settings contract (disable this if there is already a deployment)
        address bonsaiNFT = 0xE9d2FA815B95A9d087862a09079549F351DaB9bd; // base sepolia

        vm.startBroadcast(deployerPrivateKey);

        DefaultSettings defaultSettings = new DefaultSettings(bonsaiNFT);
        console2.log("defaultSettings address:", address(defaultSettings));

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, address(defaultSettings));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(DefaultHook).creationCode, constructorArgs);

        console2.log("mined hook address:", hookAddress);

        // Deploy the hook using CREATE2
        DefaultHook defaultHook = new DefaultHook{salt: salt}(IPoolManager(POOLMANAGER), address(defaultSettings));
        require(address(defaultHook) == hookAddress, "DefaultHookScript: hook address mismatch");

        vm.stopBroadcast();
    }
}
