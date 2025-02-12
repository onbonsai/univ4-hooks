// SPDX-License-Identifier: MIT

/*
░▒▓███████▓▒░ ░▒▓██████▓▒░░▒▓███████▓▒░ ░▒▓███████▓▒░░▒▓██████▓▒░░▒▓█▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░      ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░
░▒▓███████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░░▒▓████████▓▒░▒▓█▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░
░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░      ░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░
░▒▓███████▓▒░ ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓███████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░
*/

pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {DefaultSettings} from "./utils/DefaultSettings.sol";

/**
 * @title HodlHook
 * @author @c0rv0s
 * @notice Penalty for selling depending on how long you held, from 100% to 0% over time period. Time period in init args.
 *
 *  TODO:
 *  What if you didn't buy on that wallet? What if it was gifted to you? What if you bought on launchpad, no buy record?
 */
contract HodlHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    error MustUseDynamicFee();

    // Mapping to track when users acquired tokens
    mapping(address => mapping(address => uint256)) public lastBuyTime; // user => token => timestamp
    uint256 public immutable holdingPeriod; // Period after which there's no penalty (in seconds)
    uint24 public immutable maxPenalty; // Maximum penalty percentage (e.g., 10000 for 100%)

    DefaultSettings immutable defaultSettings;

    address public immutable quoteToken;

    constructor(
        IPoolManager _poolManager,
        address _defaultSettings,
        uint256 _holdingPeriod,
        uint24 _maxPenalty,
        address _quoteToken
    ) BaseHook(_poolManager) {
        defaultSettings = DefaultSettings(_defaultSettings);
        holdingPeriod = _holdingPeriod;
        maxPenalty = _maxPenalty;
        quoteToken = _quoteToken;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Check if the pool is enabled for dynamic fee
    function beforeInitialize(address, PoolKey calldata key, uint160) external pure override returns (bytes4) {
        if (key.fee != 0x800000) revert MustUseDynamicFee();

        return BaseHook.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Get base protocol fee
        uint24 protocolFee = defaultSettings.beforeSwapFeeOverride();

        // Determine if this is a sell by checking if tokenIn is NOT the quote token
        address tokenIn = params.zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        bool isSell = tokenIn != quoteToken;

        // Only apply penalty for sells
        if (!isSell) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, protocolFee);
        }

        // Get the last buy time for this user and token
        address sender = tx.origin;
        uint256 userLastBuyTime = lastBuyTime[sender][tokenIn];

        // If user has never bought (or no record), use max penalty
        if (userLastBuyTime == 0) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, maxPenalty);
        }

        // Calculate how long they've held
        uint256 timeHeld = block.timestamp - userLastBuyTime;

        // If held longer than holding period, no additional penalty
        if (timeHeld >= holdingPeriod) {
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, protocolFee);
        }

        // Calculate penalty based on time held (linear decrease)
        uint24 penaltyFee = uint24((maxPenalty * (holdingPeriod - timeHeld)) / holdingPeriod);

        // Add penalty to base protocol fee
        uint24 totalFee = protocolFee + penaltyFee;

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, totalFee);
    }

    // Function to update buy time after a successful buy
    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, BalanceDelta, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        // Determine if this is a buy by checking if tokenOut is NOT the quote token
        address tokenOut = params.zeroForOne ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);
        bool isBuy = tokenOut != quoteToken;

        // Only update buy time for buys
        address sender = tx.origin;
        if (isBuy) {
            lastBuyTime[sender][tokenOut] = block.timestamp;
        }

        return (BaseHook.afterSwap.selector, 0);
    }
}
