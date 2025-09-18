// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";

import {IUniversalRouter, Commands} from "../../src/interfaces/UniversalRouter.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Constants} from "../base/Constants.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";

import {Tax} from "../../src/Tax.sol";

import {Constants} from "../base/Constants.sol";
import {Config} from "../base/Config.sol";

/// @notice Runs a full lifecycle for the Tax hook
contract TaxLifecycle is Script, Constants, Config {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployerAddress = vm.addr(deployerPrivateKey);

    Tax taxHook;

    uint24 lpFee = 10000; // 1% static LP fee (pips)
    int24 tickSpacing = 60;

    address recipient = address(1234); // For checking tax receipt

    function deployTokens() public {
        MockERC20 token0Contract = new MockERC20("Token 0", "T0", 18);
        MockERC20 token1Contract = new MockERC20("USDC", "USDC", 6); // Assuming USDC has 6 decimals
        token0Contract.mint(deployerAddress, 10e29);
        token1Contract.mint(deployerAddress, 10e29);

        token0 = IERC20(address(token0Contract));
        token1 = IERC20(address(token1Contract));

        currency0 = Currency.wrap(address(token0));
        currency1 = Currency.wrap(address(token1));

        console.log("deployer token0 balance", token0.balanceOf(deployerAddress));
        console.log("deployer token1 balance", token1.balanceOf(deployerAddress));

        console.log("token0 address", address(token0));
        console.log("token1 address", address(token1));
    }

    function run() public {
        deployTokens();
        console2.log("Starting full run");
        step1();
        console2.log("Step 1 complete");
        step2();
        console2.log("Step 2 complete");
        step3();
        console2.log("Step 3 complete");
    }

    /// @notice deploy the hook
    function step1() public {
        vm.startBroadcast(deployerPrivateKey);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER, address(token1), uint24(200), uint24(900), recipient);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(Tax).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        taxHook = new Tax{salt: salt}(IPoolManager(POOLMANAGER), address(token1), uint24(200), uint24(900), recipient); // Match config
        require(address(taxHook) == hookAddress, "TaxLifecycle: hook address mismatch");

        vm.stopBroadcast();

        hookContract = IHooks(taxHook);
    }

    /// @notice create a pool and add liquidity
    function step2() public {
        // --- pool configuration --- //
        uint160 startingPrice = 79228162514264337593543950336; // floor(sqrt(1) * 2^96)

        // --- liquidity position configuration --- //
        uint256 token0Amount = 1000e18;
        uint256 token1Amount = 1000e6; // Adjust for USDC decimals

        // range of the position - full range
        int24 tickLower = -887220; // must be a multiple of tickSpacing
        int24 tickUpper = 887220;

        // tokens should be sorted
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        // --------------------------------- //

        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        // slippage limits
        uint256 amount0Max = token0Amount + 1 wei;
        uint256 amount1Max = token1Amount + 1 wei;

        (bytes memory actions, bytes[] memory mintParams) =
            _mintLiquidityParams(pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, address(this), ""); // empty hookData

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // initialize pool
        params[0] = abi.encodeWithSelector(posm.initializePool.selector, pool, startingPrice, "");

        // mint liquidity
        params[1] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 60
        );

        // if the pool is an ETH pair, native tokens are to be transferred
        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

        vm.startBroadcast(deployerPrivateKey);

        tokenApprovals();

        // multicall to atomically create pool & add liquidity
        posm.multicall{value: valueToPass}(params);

        vm.stopBroadcast();
    }

    /// @notice perform swaps to test taxes
    function step3() public {
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        vm.startBroadcast(deployerPrivateKey);

        // approve all the things
        token0.approve(swapRouter, type(uint256).max);
        token1.approve(swapRouter, type(uint256).max);
        PERMIT2.approve(address(token0), address(swapRouter), type(uint160).max, type(uint48).max);
        PERMIT2.approve(address(token1), address(swapRouter), type(uint160).max, type(uint48).max);

        console.log("Recipient balance before swaps (should increase by taxes):", token1.balanceOf(recipient));

        // Test 1: Exact Input Buy (swap exact USDC for TOKEN)
        console.log("Test Exact Input Buy");
        swap(pool, 100e6, 0, false, true); // amountIn=100 USDC, zeroForOne=false (USDC in, TOKEN out)

        console.log("Recipient balance after swap 1:", token1.balanceOf(recipient));

        // Test 2: Exact Output Buy (swap for exact TOKEN, paying USDC)
        console.log("Test Exact Output Buy");
        try this.swap(pool, 50e18, 0, false, false) {
            // success, do nothing
        } catch Error(string memory reason) {
            console.log("Exact Output Buy reverted with reason:", reason);
        } catch {
            console.log("Exact Output Buy reverted with low-level error");
        }

        console.log("Swap 2");

        uint256 deployerBalanceBefore = token1.balanceOf(deployerAddress);
        uint256 recipientBalanceBefore = token1.balanceOf(recipient);

        console.log("deployer USDC balance before swaps:", deployerBalanceBefore);
        console.log("Recipient USDC balance before swaps:", recipientBalanceBefore);

        // Test 3: Exact Input Sell (swap exact TOKEN for USDC)
        console.log("Test Exact Input Sell");
        swap(pool, 50e18, 0, true, true); // amountIn=50 TOKEN, zeroForOne=true (TOKEN in, USDC out)

        uint256 deployerBalanceAfter = token1.balanceOf(deployerAddress);
        uint256 recipientBalanceAfter = token1.balanceOf(recipient);

        console.log("deployer USDC balance after swap:", deployerBalanceAfter);
        console.log("Recipient USDC balance after swap:", recipientBalanceAfter);

        console.log("deployer USDC balance diff:", int256(deployerBalanceAfter) - int256(deployerBalanceBefore));
        console.log("Recipient USDC balance diff:", int256(recipientBalanceAfter) - int256(recipientBalanceBefore));

        console.log("End Swap 2");

        // Test 4: Exact Output Sell (swap for exact USDC, paying TOKEN)
        console.log("Test Exact Output Sell");
        try this.swap(pool, 100e6, 0, true, false) {
            // success, do nothing
        } catch Error(string memory reason) {
            console.log("Exact Output Sell reverted with reason:", reason);
        } catch {
            console.log("Exact Output Sell reverted with low-level error");
        }

        console.log("Recipient balance after swaps:", token1.balanceOf(recipient));

        vm.stopBroadcast();
    }

    /// @dev helper function for encoding mint liquidity operation
    /// @dev does NOT encode SWEEP, developers should take care when minting liquidity on an ETH pair
    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address _recipient,
        bytes memory
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, _recipient, ""); // empty hookData
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        return (actions, params);
    }

    function tokenApprovals() public {
        if (!currency0.isAddressZero()) {
            token0.approve(address(PERMIT2), type(uint256).max);
            PERMIT2.approve(address(token0), address(posm), type(uint160).max, type(uint48).max);
        }
        if (!currency1.isAddressZero()) {
            token1.approve(address(PERMIT2), type(uint256).max);
            PERMIT2.approve(address(token1), address(posm), type(uint160).max, type(uint48).max);
        }
    }

    // Generalized swap function: amount is amountIn if exactIn=true, amountOut if exactIn=false
    // minAmountOut is for slippage check
    function swap(PoolKey memory key, uint256 amount, uint256 minAmountOut, bool zeroForOne, bool exactIn)
        public
        returns (uint256 amountOut)
    {
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        if (exactIn) {
            params[0] = abi.encode(
                IV4Router.ExactInputSingleParams({
                    poolKey: key,
                    zeroForOne: zeroForOne,
                    amountIn: uint128(amount),
                    amountOutMinimum: uint128(minAmountOut),
                    hookData: bytes("")
                })
            );
            params[1] = abi.encode(zeroForOne ? key.currency0 : key.currency1, amount);
            params[2] = abi.encode(zeroForOne ? key.currency1 : key.currency0, minAmountOut);
        } else {
            // For exact output, adjust actions accordingly (use ExactOutputSingleParams)
            actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL)
            );
            params[0] = abi.encode(
                IV4Router.ExactOutputSingleParams({
                    poolKey: key,
                    zeroForOne: zeroForOne,
                    amountOut: uint128(amount),
                    amountInMaximum: uint128(type(uint128).max), // No max to simplify
                    hookData: bytes("")
                })
            );
            params[1] = abi.encode(zeroForOne ? key.currency0 : key.currency1, type(uint128).max);
            params[2] = abi.encode(zeroForOne ? key.currency1 : key.currency0, amount);
        }

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        IUniversalRouter(swapRouter).execute(commands, inputs, block.timestamp + 600000);

        // Verify and return the output amount (simplified; adjust based on direction)
        Currency outputCurrency = zeroForOne ? key.currency1 : key.currency0;
        amountOut = IERC20(Currency.unwrap(outputCurrency)).balanceOf(deployerAddress);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }
}
