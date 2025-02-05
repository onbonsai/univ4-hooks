// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {DefaultSettings} from "../utils/DefaultSettings.sol";

import {TradingDays, LibDateTime, HolidayCalendar, DaylightSavingsCalendar} from "./TradingDays.sol";

/**
 * @title TradingHoursHook
 * @notice This hook only allows trading during New York trading hours. Fork of https://github.com/horsefacts/trading-days
 */
contract TradingHoursHook is BaseHook, TradingDays {
    using PoolIdLibrary for PoolKey;
    using LibDateTime for uint256;

    /// @notice Ring the opening bell.
    event DingDingDing(address indexed ringer);

    /// @notice Year/month/day mapping recording whether the market opened.
    mapping(uint256 => mapping(uint256 => mapping(uint256 => bool))) public marketOpened;

    DefaultSettings immutable defaultSettings;

    constructor(
        IPoolManager _poolManager,
        address _defaultSettings,
        HolidayCalendar _holidays,
        DaylightSavingsCalendar _dst
    ) BaseHook(_poolManager) TradingDays(_holidays, _dst) {
        defaultSettings = DefaultSettings(_defaultSettings);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        State s = state();

        if (s == State.OPEN) {
            _ringOpeningBell(sender);
        } else if (s == State.HOLIDAY) {
            revert ClosedForHoliday(getHoliday());
        } else if (s == State.WEEKEND) {
            revert ClosedForWeekend();
        } else if (s == State.AFTER_HOURS) {
            revert AfterHours();
        }

        // override swap fee by making a call to the DefaultSettings contract
        uint24 protocolFeePercentage = defaultSettings.beforeSwapFeeOverride();

        // The protocol fee will be applied as part of the LP fees in the PoolManager
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, protocolFeePercentage);
    }

    /// @dev The first swap of the trading day rings the opening bell.
    function _ringOpeningBell(address ringer) internal {
        (uint256 year, uint256 month, uint256 day) = time().timestampToDate();
        // If the market already opened today, don't ring the bell again.
        if (marketOpened[year][month][day]) return;

        // Wow! You get to ring the opening bell!
        marketOpened[year][month][day] = true;
        emit DingDingDing(ringer);
    }
}
