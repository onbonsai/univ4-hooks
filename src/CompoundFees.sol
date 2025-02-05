// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {DefaultSettings} from "./utils/DefaultSettings.sol";

/**
 * @title CompoundFees
 * @author @c0rv0s
 * @notice Collects trading fees only in quote token and compounds them for better liquidity
 */
contract CompoundFees is BaseHook {
    using PoolIdLibrary for PoolKey;

    DefaultSettings immutable defaultSettings;

    constructor(IPoolManager _poolManager, address _defaultSettings) BaseHook(_poolManager) {
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
        // override swap fee by making a call to the DefaultSettings contract
        uint24 protocolFeePercentage = defaultSettings.beforeSwapFeeOverride();

        // The protocol fee will be applied as part of the LP fees in the PoolManager
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, protocolFeePercentage);
    }
}
