// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {Constants} from "./base/Constants.sol";

/// @notice Creates a pool with Tax Hook using USDC and ZSTRAT tokens on Base
contract CreateZstratTaxPoolScript is Script, Constants {
    using CurrencyLibrary for Currency;

    /////////////////////////////////////
    // --- Parameters to Configure --- //
    /////////////////////////////////////

    uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

    // Token addresses on Base
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
    address constant ZSTRAT_BASE = 0x076cA43b614D63b164332aAB31BBcA841f8Df871; // ZSTRAT token
    address constant TAX_HOOK = 0x3F6C4280A39be7354da82a74b685bc72563f80CC; // Deployed Tax Hook

    // Pool configuration
    uint24 lpFee = 10000; // 1% fee (in pips)
    int24 tickSpacing = 60; // Standard tick spacing for 1% fee

    // use calc.py to calculate the starting price based on the starting amounts
    uint160 startingPrice = 7922816251426434048;

    // Liquidity amounts
    uint256 public usdcAmount = 10e6; // 10 USDC (6 decimals)
    uint256 public zstratAmount = 1e9 * 1e18; // 1 billion ZSTRAT (18 decimals)

    // Full range position
    int24 tickLower = -887220; // Must be multiple of tickSpacing
    int24 tickUpper = 887220;

    // Token contracts
    IERC20 usdc = IERC20(USDC_BASE);
    IERC20 zstrat = IERC20(ZSTRAT_BASE);
    IHooks hookContract = IHooks(TAX_HOOK);

    // Currencies (sorted)
    Currency currency0;
    Currency currency1;
    IERC20 token0;
    IERC20 token1;
    uint256 token0Amount;
    uint256 token1Amount;

    /////////////////////////////////////

    function setUp() public {
        // Sort currencies - USDC (0x833...) vs ZSTRAT (0x076...)
        // ZSTRAT address is smaller, so it becomes currency0
        if (ZSTRAT_BASE < USDC_BASE) {
            currency0 = Currency.wrap(ZSTRAT_BASE);
            currency1 = Currency.wrap(USDC_BASE);
            token0 = zstrat;
            token1 = usdc;
            token0Amount = zstratAmount;
            token1Amount = usdcAmount;
        } else {
            currency0 = Currency.wrap(USDC_BASE);
            currency1 = Currency.wrap(ZSTRAT_BASE);
            token0 = usdc;
            token1 = zstrat;
            token0Amount = usdcAmount;
            token1Amount = zstratAmount;
        }

        console2.log("Currency0 (token0):", Currency.unwrap(currency0));
        console2.log("Currency1 (token1):", Currency.unwrap(currency1));
        console2.log("Token0 amount:", token0Amount);
        console2.log("Token1 amount:", token1Amount);
    }

    function run() external {
        setUp();

        // Create pool key
        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });
        bytes memory hookData = new bytes(0);

        console2.log("Creating pool with:");
        console2.log("- Fee:", lpFee, "pips (1%)");
        console2.log("- Hook:", address(hookContract));
        console2.log("- Starting price:", startingPrice);

        // Convert token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        console2.log("Calculated liquidity:", liquidity);

        // Slippage limits
        uint256 amount0Max = token0Amount + 1 wei;
        uint256 amount1Max = token1Amount + 1 wei;

        (bytes memory actions, bytes[] memory mintParams) =
            _mintLiquidityParams(pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, msg.sender, hookData);

        // Multicall parameters
        bytes[] memory params = new bytes[](2);

        // Initialize pool
        params[0] = abi.encodeWithSelector(posm.initializePool.selector, pool, startingPrice, hookData);

        // Mint liquidity
        params[1] = abi.encodeWithSelector(
            posm.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp + 60
        );

        // No ETH pairs, so no value to pass
        uint256 valueToPass = 0;

        vm.startBroadcast(deployerPrivateKey);

        // Approve tokens
        tokenApprovals();

        console2.log("Executing pool creation and liquidity addition...");

        // Execute multicall to atomically create pool & add liquidity
        posm.multicall{value: valueToPass}(params);

        console2.log("Pool created successfully!");
        console2.log("Pool Key Hash:", uint256(keccak256(abi.encode(pool))));

        vm.stopBroadcast();
    }

    /// @dev Helper function for encoding mint liquidity operation
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
        console2.log("Approving tokens...");
        
        // Approve token0
        token0.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(token0), address(posm), type(uint160).max, type(uint48).max);
        
        // Approve token1
        token1.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(token1), address(posm), type(uint160).max, type(uint48).max);

        console2.log("Token approvals completed");
    }
}
