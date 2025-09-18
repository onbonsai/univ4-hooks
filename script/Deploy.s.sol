// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Constants} from "./base/Constants.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

import {DefaultSettings} from "../src/utils/DefaultSettings.sol";
import {TradingDaysHook} from "../src/TradingDaysHook.sol";
import {HolidayCalendar, DaylightSavingsCalendar} from "trading-days/TradingDays.sol";

import {LotteryHook} from "../src/LotteryHook.sol";

import {BuybackAndBurn} from "../src/BuybackAndBurn.sol";
import {Tax} from "../src/Tax.sol";

/// @notice Mines the address and deploys the Tax.sol Hook contract
contract TaxDeploy is Script, Constants {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {}

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        address quote = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on base
        uint24 buyTax = uint24(200);
        uint24 sellTax = uint24(900);
        address recipient = address(0x123); // TODO: protocol address

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, quote, buyTax, sellTax, recipient); // Example; adjust as needed
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(Tax).creationCode, constructorArgs);

        console2.log("mined hook address:", hookAddress);

        // Deploy the hook using CREATE2
        Tax newHook = new Tax{salt: salt}(IPoolManager(POOLMANAGER), quote, buyTax, sellTax, recipient);
        require(address(newHook) == hookAddress, "DeployScript: hook address mismatch");

        vm.stopBroadcast();
    }
}

/// @notice Mines the address and deploys the TradingDaysHook.sol Hook contract
contract TradingDays is Script, Constants {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {}

    function run() public {
        address bonsaiNFT = 0xE9d2FA815B95A9d087862a09079549F351DaB9bd; // base sepolia
        if (block.chainid == 8453) bonsaiNFT = 0xf060fd6b66B13421c1E514e9f10BedAD52cF241e; // base mainnet

        vm.startBroadcast(deployerPrivateKey);

        // DefaultSettings defaultSettings = new DefaultSettings(bonsaiNFT); // disable this if there is already a deployment
        DefaultSettings defaultSettings = DefaultSettings(0x419F1450368F63A8C7aB67BD96B6d0ff2E062329); // Base Mainnet
        console2.log("defaultSettings address:", address(defaultSettings));

        // Holidays
        HolidayCalendar holidays = new HolidayCalendar();
        // Daylight Savings
        DaylightSavingsCalendar dst = new DaylightSavingsCalendar();

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, address(defaultSettings), holidays, dst);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(TradingDaysHook).creationCode, constructorArgs);

        console2.log("mined hook address:", hookAddress);

        // Deploy the hook using CREATE2
        TradingDaysHook newHook =
            new TradingDaysHook{salt: salt}(IPoolManager(POOLMANAGER), address(defaultSettings), holidays, dst);
        require(address(newHook) == hookAddress, "DeployScript: hook address mismatch");

        vm.stopBroadcast();
    }
}

/// @notice Mines the address and deploys the LotteryHook.sol Hook contract
contract Lottery is Script, Constants {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {}

    function run() public {
        address bonsaiNFT = 0xE9d2FA815B95A9d087862a09079549F351DaB9bd; // base sepolia
        if (block.chainid == 8453) bonsaiNFT = 0xf060fd6b66B13421c1E514e9f10BedAD52cF241e; // base mainnet

        vm.startBroadcast(deployerPrivateKey);

        // DefaultSettings defaultSettings = new DefaultSettings(bonsaiNFT); // disable this if there is already a deployment
        DefaultSettings defaultSettings = DefaultSettings(0x419F1450368F63A8C7aB67BD96B6d0ff2E062329); // Base Mainnet
        console2.log("defaultSettings address:", address(defaultSettings));

        // hook contracts must have specific flags encoded in the address
        uint160 flags =
            uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, address(defaultSettings));
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(LotteryHook).creationCode, constructorArgs);

        console2.log("mined hook address:", hookAddress);

        // Deploy the hook using CREATE2
        LotteryHook newHook = new LotteryHook{salt: salt}(IPoolManager(POOLMANAGER), address(defaultSettings));
        require(address(newHook) == hookAddress, "DeployScript: hook address mismatch");

        vm.stopBroadcast();
    }
}

/// @notice Mines the address and deploys the BuybackAndBurn.sol Hook contract
contract BuybackAndBurnDeploy is Script, Constants {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    function setUp() public {}

    function run() public {
        address bonsaiNFT = 0xE9d2FA815B95A9d087862a09079549F351DaB9bd; // base sepolia
        if (block.chainid == 8453) bonsaiNFT = 0xf060fd6b66B13421c1E514e9f10BedAD52cF241e; // base mainnet

        vm.startBroadcast(deployerPrivateKey);

        // DefaultSettings defaultSettings = new DefaultSettings(bonsaiNFT); // disable this if there is already a deployment
        DefaultSettings defaultSettings = DefaultSettings(0x419F1450368F63A8C7aB67BD96B6d0ff2E062329); // Base Mainnet
        console2.log("defaultSettings address:", address(defaultSettings));

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        address bonsaiToken = block.chainid == 8453
            ? 0x474f4cb764df9da079D94052fED39625c147C12C
            : 0x3d2bD0e15829AA5C362a4144FdF4A1112fa29B5c;
        uint256 swapThreshold = 500;
        bytes memory constructorArgs =
            abi.encode(POOLMANAGER, address(defaultSettings), bonsaiToken, swapRouter, swapThreshold);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BuybackAndBurn).creationCode, constructorArgs);

        console2.log("mined hook address:", hookAddress);

        // Deploy the hook using CREATE2
        BuybackAndBurn newHook = new BuybackAndBurn{salt: salt}(
            IPoolManager(POOLMANAGER), address(defaultSettings), bonsaiToken, swapRouter, swapThreshold
        );
        require(address(newHook) == hookAddress, "DeployScript: hook address mismatch");

        vm.stopBroadcast();
    }
}
