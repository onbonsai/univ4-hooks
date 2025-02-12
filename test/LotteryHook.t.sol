// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {LotteryHook} from "../src/LotteryHook.sol";
import {DefaultSettings} from "../src/utils/DefaultSettings.sol";
import {TestERC20} from "v4-core/src/test/TestERC20.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

import {MockERC721} from "./mocks/MockERC721.sol";

contract LotteryHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    LotteryHook hook;
    DefaultSettings settings;
    PoolKey poolKey;

    int24 tickLower;
    int24 tickUpper;

    MockERC721 public bonsaiNFT;

    uint160 constant SQRT_RATIO_1_1 = 79228162514264337593543950336;

    address defaultSender = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        vm.prank(defaultSender);
        deployAndApprovePosm(manager);

        bonsaiNFT = new MockERC721("Bonsai NFT", "BNFT");
        settings = new DefaultSettings(address(bonsaiNFT));

        // Deploy hook with correct flags (beforeSwap and afterSwap)
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG);
        address hookAddress = address(uint160(flags | (uint160(0x4444) << 144)));

        // Prepare constructor arguments
        bytes memory constructorArgs = abi.encode(address(manager), address(settings));

        // Deploy hook to the correct address
        deployCodeTo("LotteryHook.sol:LotteryHook", constructorArgs, hookAddress);
        hook = LotteryHook(hookAddress);

        // Setup pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0x800000, // dynamic fee
            tickSpacing: 60,
            hooks: IHooks(hook)
        });

        // Initialize pool
        manager.initialize(poolKey, SQRT_RATIO_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        posm.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function test_InitializeLottery() public {
        (,,,,, bool initialized) = hook.getPoolLotteryState(poolKey.toId());
        assertTrue(initialized, "Pool should be initialized");
    }

    function test_CollectFees() public {
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        swap(poolKey, zeroForOne, amountSpecified, ZERO_BYTES);

        // Check fees were collected
        (,,, uint256 feesCurrency0, uint256 feesCurrency1,) = hook.getPoolLotteryState(poolKey.toId());
        assertGt(feesCurrency0, 0, "Should have collected fees");
        assertGt(feesCurrency1, 0, "Should have collected fees");
    }

    function test_RunLottery() public {
        // Setup multiple swaps to trigger lottery
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        for (uint256 i = 0; i < hook.SWAPS_THRESHOLD(); i++) {
            swap(poolKey, zeroForOne, amountSpecified, ZERO_BYTES);
            zeroForOne = !zeroForOne;
        }

        // Check lottery was run (fees should be reset)
        (,,, uint256 feesCurrency0, uint256 feesCurrency1,) = hook.getPoolLotteryState(poolKey.toId());
        assertEq(feesCurrency0, 0, "Fees should be reset after lottery");
    }
}
