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
import {MockERC721} from "../../test/mocks/MockERC721.sol";

import {Constants} from "../base/Constants.sol";
import {HookMiner} from "../../test/utils/HookMiner.sol";

import {DefaultSettings} from "../../src/utils/DefaultSettings.sol";
import {BuybackAndBurn} from "../../src/BuybackAndBurn.sol";

import {Constants} from "../base/Constants.sol";
import {Config} from "../base/Config.sol";

/// @notice Runs a full lifecycle for a hook
contract BuybackAndBurnLifecycle is Script, Constants, Config {
    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployerAddress = vm.addr(deployerPrivateKey);

    BuybackAndBurn buybackAndBurnHook;

    uint24 lpFee = 0x800000;
    int24 tickSpacing = 60;

    uint256 swapThreshold = 2;

    function deployTokens() public {
        MockERC20 token0Contract = new MockERC20("Token 0", "T0", 18);
        MockERC20 token1Contract = new MockERC20("Token 1", "T1", 18);
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
        step4();
        console2.log("Step 4 complete");
    }

    /// @notice deploy the hook
    function step1() public {
        // deploy default settings contract (disable this if there is already a deployment)
        address bonsaiNFT = 0xE9d2FA815B95A9d087862a09079549F351DaB9bd; // base sepolia

        // base mainnet
        if (block.chainid == 8453) bonsaiNFT = 0xf060fd6b66B13421c1E514e9f10BedAD52cF241e;

        // deploy mock bonsai nft
        bonsaiNFT = address(new MockERC721("Bonsai NFT", "BNS"));

        vm.startBroadcast(deployerPrivateKey);

        DefaultSettings defaultSettings = new DefaultSettings(bonsaiNFT);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs =
            abi.encode(POOLMANAGER, address(defaultSettings), address(token0), swapRouter, swapThreshold);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(BuybackAndBurn).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        buybackAndBurnHook = new BuybackAndBurn{salt: salt}(
            IPoolManager(POOLMANAGER), address(defaultSettings), address(token0), swapRouter, swapThreshold
        );
        require(address(buybackAndBurnHook) == hookAddress, "buybackAndBurnHookScript: hook address mismatch");

        vm.stopBroadcast();

        hookContract = IHooks(buybackAndBurnHook);
    }

    /// @notice create a pool and add liquidity
    function step2() public {
        // --- pool configuration --- //
        // starting price of the pool, in sqrtPriceX96
        uint160 startingPrice = 79228162514264337593543950336; // floor(sqrt(1) * 2^96)

        // --- liquidity position configuration --- //
        uint256 token0Amount = 1000e18;
        uint256 token1Amount = 1000e18;

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
        bytes memory hookData = new bytes(0);

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
            _mintLiquidityParams(pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, address(this), hookData);

        // multicall parameters
        bytes[] memory params = new bytes[](2);

        // initialize pool
        params[0] = abi.encodeWithSelector(posm.initializePool.selector, pool, startingPrice, hookData);

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

    /// @notice swap tokens
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

        console.log("before swap zero for one");
        console.log("hook balance token0", token0.balanceOf(address(buybackAndBurnHook)));
        console.log("hook balance token1", token1.balanceOf(address(buybackAndBurnHook)));

        // swap tokens
        uint256 amountOut = swapExactInputSingle(pool, 1e18, 0, true);
        console.log("amountOut", amountOut);

        console.log("after swap");
        console.log("hook balance token0", token0.balanceOf(address(buybackAndBurnHook)));
        console.log("hook balance token1", token1.balanceOf(address(buybackAndBurnHook)));

        uint256 amountOut2 = swapExactInputSingle(pool, 1e18, 0, false);
        console.log("amountOut2", amountOut2);

        console.log("after swap 2 one for zero");
        console.log("hook balance token0", token0.balanceOf(address(buybackAndBurnHook)));
        console.log("hook balance token1", token1.balanceOf(address(buybackAndBurnHook)));

        vm.stopBroadcast();
    }

    /// @notice buyback and burn tokens
    function step4() public {
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        vm.startBroadcast(deployerPrivateKey);

        buybackAndBurnHook.buybackAndBurn(pool, 9e16);

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
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
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

    function swapExactInputSingle(PoolKey memory key, uint128 amountIn, uint128 minAmountOut, bool zeroForOne)
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
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(zeroForOne ? key.currency0 : key.currency1, amountIn);
        params[2] = abi.encode(zeroForOne ? key.currency1 : key.currency0, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        IUniversalRouter(swapRouter).execute(commands, inputs, block.timestamp + 600000);

        // Verify and return the output amount
        amountOut = IERC20(Currency.unwrap(key.currency1)).balanceOf(deployerAddress);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }
}
