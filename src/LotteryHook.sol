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
import {Currency} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DefaultSettings} from "./utils/DefaultSettings.sol";

/**
 * @title LotteryHook
 * @author @c0rv0s
 * @notice Pays out fees to random winner. Every 72 hours or 1k swaps, start the lottery. 10% chance on each swap to pay out all fees
 */
contract LotteryHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for int128;

    error MustUseDynamicFee();
    error NoSwappersInLottery();

    struct LotteryState {
        address[] swappers;
        uint256 lastLotteryTimestamp;
        uint256 swapCount;
        uint256 accumulatedFeesCurrency0;
        uint256 accumulatedFeesCurrency1;
        bool isInitialized;
    }

    // Constants for lottery settings
    uint256 public constant TIME_THRESHOLD = 72 hours;
    uint256 public constant SWAPS_THRESHOLD = 1000;
    uint256 public constant LOTTERY_CHANCE = 10; // 10% chance (1/10)

    // Mapping of pool ID to its lottery state
    mapping(PoolId => LotteryState) public poolLotteries;

    DefaultSettings immutable defaultSettings;

    uint24 public constant LOTTERY_FEE_BIPS = 100; // 1% fee for lottery
    uint24 public constant TOTAL_BIPS = 100_00;

    event LotteryWinner(address winner, uint256 amountCurrency0, uint256 amountCurrency1, PoolId poolId);
    event PoolLotteryInitialized(PoolId poolId);

    constructor(IPoolManager _poolManager, address _defaultSettings) BaseHook(_poolManager) {
        defaultSettings = DefaultSettings(_defaultSettings);
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
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Check if the pool is enabled for dynamic fee
    function beforeInitialize(address, PoolKey calldata key, uint160) external override returns (bytes4) {
        if (key.fee != 0x800000) revert MustUseDynamicFee();

        // Initialize lottery state for this pool
        PoolId poolId = key.toId();
        poolLotteries[poolId].isInitialized = true;
        poolLotteries[poolId].lastLotteryTimestamp = block.timestamp;

        emit PoolLotteryInitialized(poolId);

        return BaseHook.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();

        // Track swapper
        address sender = tx.origin;
        poolLotteries[poolId].swappers.push(sender);
        poolLotteries[poolId].swapCount++;

        // lottery fee
        uint256 swapAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
        uint256 feeAmount = (swapAmount * LOTTERY_FEE_BIPS) / TOTAL_BIPS;

        Currency feeCurrency = params.zeroForOne ? key.currency0 : key.currency1;
        poolManager.take(feeCurrency, address(this), feeAmount);

        // Add to accumulated fees for this pool
        if (feeCurrency == key.currency0) {
            poolLotteries[poolId].accumulatedFeesCurrency0 += feeAmount;
        } else {
            poolLotteries[poolId].accumulatedFeesCurrency1 += feeAmount;
        }

        BeforeSwapDelta returnDelta = toBeforeSwapDelta(
            int128(int256(feeAmount)), // Specified delta (fee amount)
            0 // Unspecified delta (no change)
        );

        // Check if lottery should run
        bool shouldRunLottery = (
            block.timestamp >= poolLotteries[poolId].lastLotteryTimestamp + TIME_THRESHOLD
                || poolLotteries[poolId].swapCount >= SWAPS_THRESHOLD
        );

        // 10% chance to run lottery if conditions are met
        if (shouldRunLottery && _random() % LOTTERY_CHANCE == 0) {
            _runLottery(poolId, key);
        }

        // Get base protocol fee
        uint24 protocolFee = defaultSettings.beforeSwapFeeOverride();

        return (BaseHook.beforeSwap.selector, returnDelta, protocolFee);
    }

    function _runLottery(PoolId poolId, PoolKey calldata key) internal {
        LotteryState storage lottery = poolLotteries[poolId];

        if (lottery.swappers.length == 0) revert NoSwappersInLottery();

        // Select random winner
        uint256 winnerIndex = _random() % lottery.swappers.length;
        address winner = lottery.swappers[winnerIndex];

        // Get accumulated fees for this pool
        uint256 prizeAmountCurrency0 = lottery.accumulatedFeesCurrency0;
        uint256 prizeAmountCurrency1 = lottery.accumulatedFeesCurrency1;

        // Reset lottery state for this pool
        delete lottery.swappers;
        lottery.swapCount = 0;
        lottery.accumulatedFeesCurrency0 = 0;
        lottery.accumulatedFeesCurrency1 = 0;
        lottery.lastLotteryTimestamp = block.timestamp;

        // Transfer prize to winner
        IERC20(Currency.unwrap(key.currency0)).transfer(winner, prizeAmountCurrency0);
        IERC20(Currency.unwrap(key.currency1)).transfer(winner, prizeAmountCurrency1);

        emit LotteryWinner(winner, prizeAmountCurrency0, prizeAmountCurrency1, poolId);
    }

    function _random() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
    }

    // Helper view functions
    function getPoolLotteryState(PoolId poolId)
        external
        view
        returns (
            uint256 swapperCount,
            uint256 lastLotteryTime,
            uint256 currentSwapCount,
            uint256 currentFeesCurrency0,
            uint256 currentFeesCurrency1,
            bool initialized
        )
    {
        LotteryState storage lottery = poolLotteries[poolId];
        return (
            lottery.swappers.length,
            lottery.lastLotteryTimestamp,
            lottery.swapCount,
            lottery.accumulatedFeesCurrency0,
            lottery.accumulatedFeesCurrency1,
            lottery.isInitialized
        );
    }

    function getPoolSwappers(PoolId poolId) external view returns (address[] memory) {
        return poolLotteries[poolId].swappers;
    }
}
