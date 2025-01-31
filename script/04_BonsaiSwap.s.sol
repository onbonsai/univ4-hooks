// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";

import {Constants} from "./base/Constants.sol";
import {Config} from "./base/Config.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IUniversalRouter, Commands} from "../src/interfaces/UniversalRouter.sol";

struct SwapInfoV4 {
    PathKey[] path;
    IUniversalRouter router;
}

contract SwapScript is Script, Constants, Config {
    // slippage tolerance to allow for unlimited price impact
    uint160 public constant MIN_PRICE_LIMIT = TickMath.MIN_SQRT_PRICE + 1;
    uint160 public constant MAX_PRICE_LIMIT = TickMath.MAX_SQRT_PRICE - 1;

    /////////////////////////////////////
    // --- Parameters to Configure --- //
    /////////////////////////////////////

    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    address deployerAddress = vm.addr(deployerPrivateKey);

    address swapRouter = 0x492E6456D9528771018DeB9E87ef7750EF184104; // base sepolia universal router

    // --- pool configuration --- //
    // fees paid by swappers that accrue to liquidity providers
    uint24 lpFee = 0x800000; // override fee flag
    int24 tickSpacing = 60;

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // required approvals
        // token0.approve(swapRouter, type(uint256).max);
        // token1.approve(swapRouter, type(uint256).max);
        // weth.approve(swapRouter, type(uint256).max);
        // PERMIT2.approve(address(token0), address(swapRouter), type(uint160).max, type(uint48).max);
        // PERMIT2.approve(address(token1), address(swapRouter), type(uint160).max, type(uint48).max);
        // PERMIT2.approve(address(weth), address(swapRouter), type(uint160).max, type(uint48).max);

        // SwapInfoV4 memory swapInfo = SwapInfoV4({path: new PathKey[](1), router: IUniversalRouter(swapRouter)});

        // swapInfo.path[0] = PathKey({
        //     intermediateCurrency: currency1,
        //     fee: lpFee,
        //     tickSpacing: tickSpacing,
        //     hooks: hookContract,
        //     hookData: hex""
        // });

        // uint256 amountOut = swapExactInputV4(1e18, 0, swapInfo, address(weth), Currency.unwrap(currency1));

        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });
        uint256 amountOut = swapExactInputSingle(pool, 1e18, 0);

        vm.stopBroadcast();
        console.log("amountOut", amountOut);
    }

    function swapExactInputSingle(PoolKey memory key, uint128 amountIn, uint128 minAmountOut)
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
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(key.currency0, amountIn);
        params[2] = abi.encode(key.currency1, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        IUniversalRouter(swapRouter).execute(commands, inputs, 1896061158); // deadline in 2030 :/

        // Verify and return the output amount
        amountOut = IERC20(Currency.unwrap(key.currency1)).balanceOf(0x21aF1185734D213D45C6236146fb81E2b0E8b821);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }

    // TODO: sus
    /// @notice swap USDC to BONSAI on UniV4
    function swapExactInputV4(
        uint128 amountIn,
        uint128 minAmountOut,
        SwapInfoV4 memory swapInfo,
        address currency0,
        address currency1
    ) internal returns (uint256 amountOut) {
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: Currency.wrap(currency0),
                path: swapInfo.path,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut
            })
        );
        params[1] = abi.encode(Currency.wrap(currency0), amountIn);
        params[2] = abi.encode(Currency.wrap(currency1), minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        swapInfo.router.execute(commands, inputs, block.timestamp);

        // Verify and return the output amount
        amountOut = IERC20(currency1).balanceOf(deployerAddress);
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }
}
