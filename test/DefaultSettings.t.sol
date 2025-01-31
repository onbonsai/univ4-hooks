// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DefaultHook} from "../src/DefaultHook.sol";
import {DefaultSettings} from "../src/utils/DefaultSettings.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {MockERC721} from "./mocks/MockERC721.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

contract DefaultHookTest is Test, Fixtures {
    DefaultHook public defaultHook;
    DefaultSettings public defaultSettings;
    MockERC721 public bonsaiNFT;
    address public constant SENDER = address(0x2);

    address defaultSender = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    function setUp() public {
        deployFreshManagerAndRouters();
        bonsaiNFT = new MockERC721("Bonsai NFT", "BNFT");

        // Deploy DefaultSettings
        defaultSettings = new DefaultSettings(address(bonsaiNFT));

        // Deploy DefaultHook
        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG | (0x4444 << 144)));
        bytes memory constructorArgs = abi.encode(address(manager), address(defaultSettings));
        deployCodeTo("DefaultHook.sol:DefaultHook", constructorArgs, hookAddress);
        defaultHook = DefaultHook(hookAddress);
    }

    function testBeforeSwap_NoNFTs() public {
        PoolKey memory key;
        IPoolManager.SwapParams memory params;

        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = defaultHook.beforeSwap(SENDER, key, params, "");

        assertEq(selector, DefaultHook.beforeSwap.selector);
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(delta), 0);
        assertEq(BeforeSwapDeltaLibrary.getUnspecifiedDelta(delta), 0);
        assertEq(fee, 15000 | LPFeeLibrary.OVERRIDE_FEE_FLAG); // 1.5% with override flag
    }

    function testBeforeSwap_OneNFT() public {
        bonsaiNFT.mint(defaultSender, 1);

        PoolKey memory key;
        IPoolManager.SwapParams memory params;

        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = defaultHook.beforeSwap(SENDER, key, params, "");

        assertEq(selector, DefaultHook.beforeSwap.selector);
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(delta), 0);
        assertEq(BeforeSwapDeltaLibrary.getUnspecifiedDelta(delta), 0);
        assertEq(fee, 0 | LPFeeLibrary.OVERRIDE_FEE_FLAG); // 0% with override flag
    }

    function testBeforeSwap_MultipleNFTs() public {
        bonsaiNFT.mint(defaultSender, 1);
        bonsaiNFT.mint(defaultSender, 2);
        bonsaiNFT.mint(defaultSender, 3);

        PoolKey memory key;
        IPoolManager.SwapParams memory params;

        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = defaultHook.beforeSwap(SENDER, key, params, "");

        assertEq(selector, DefaultHook.beforeSwap.selector);
        assertEq(BeforeSwapDeltaLibrary.getSpecifiedDelta(delta), 0);
        assertEq(BeforeSwapDeltaLibrary.getUnspecifiedDelta(delta), 0);
        assertEq(fee, 0 | LPFeeLibrary.OVERRIDE_FEE_FLAG); // 0% with override flag
    }
}
