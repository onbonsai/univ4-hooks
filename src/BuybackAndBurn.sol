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

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

import {DefaultSettings} from "./utils/DefaultSettings.sol";
import {IUniversalRouter, Commands} from "./interfaces/UniversalRouter.sol";

// import "forge-std/console2.sol";

error MustUseDynamicFee();
error MustUseFeeToken();

struct PoolInfo {
    uint256 accumulatedFees;
    uint256 swapCount;
}

/**
 * @title BuybackAndBurn
 * @author @c0rv0s
 * @notice This hook collects 1% of the swap amount in the desired fee token and then uses it for a buyback and burn of the other token.
 * @dev This hook is only compatible with pools using the dynamic fee model. All pools must use the fee token as one of the currencies.
 */
contract BuybackAndBurn is BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for int128;

    DefaultSettings immutable defaultSettings;
    Currency immutable feeCurrency;
    IUniversalRouter immutable swapRouter;
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(address(0x000000000022D473030F116dDEE9F6B43aC78BA3));

    mapping(PoolId => PoolInfo) public poolInfo;

    uint256 public immutable swapThreshold;
    uint256 public constant BURN_FEE_PERCENT = 500; // 5%

    event Burn(PoolId indexed poolId, uint256 inputAmount, uint256 burnAmount);

    constructor(
        IPoolManager _poolManager,
        address _defaultSettings,
        address _feeToken,
        address _swapRouter,
        uint256 _swapThreshold
    ) BaseHook(_poolManager) {
        require(_feeToken != address(0), "Fee token cannot be zero address");

        defaultSettings = DefaultSettings(_defaultSettings);
        feeCurrency = Currency.wrap(_feeToken);
        swapRouter = IUniversalRouter(_swapRouter);
        swapThreshold = _swapThreshold;

        IERC20(_feeToken).approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(_feeToken), address(_swapRouter), type(uint160).max, type(uint48).max);
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
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Check if the pool is enabled for dynamic fee
    function beforeInitialize(address, PoolKey calldata key, uint160) external view override returns (bytes4) {
        if (key.fee != 0x800000) revert MustUseDynamicFee();

        // check if the pool is using the fee token
        if (!(key.currency0 == feeCurrency) && !(key.currency1 == feeCurrency)) {
            revert MustUseFeeToken();
        }

        return BaseHook.beforeInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // override swap fee by making a call to the DefaultSettings contract
        uint24 protocolFeePercentage = defaultSettings.beforeSwapFeeOverride();

        if (protocolFeePercentage == LPFeeLibrary.OVERRIDE_FEE_FLAG) {
            // pay nothing and return 0 delta
            return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, protocolFeePercentage);
        }

        BeforeSwapDelta returnDelta = BeforeSwapDeltaLibrary.ZERO_DELTA;

        // take fee in fee currency if its the input currency
        if ((params.zeroForOne && key.currency0 == feeCurrency) || (!params.zeroForOne && key.currency1 == feeCurrency))
        {
            PoolId poolId = key.toId();

            // calculate fee amount for burn reserve
            uint256 swapAmount =
                params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
            uint256 feeAmount = swapAmount * BURN_FEE_PERCENT / 100_00;

            poolManager.take(feeCurrency, address(this), feeAmount);

            // increment pool info
            poolInfo[poolId].accumulatedFees += feeAmount;
            poolInfo[poolId].swapCount++;

            returnDelta = toBeforeSwapDelta(int128(int256(feeAmount)), 0);
        }

        // 0.5% fee to LP
        return (BaseHook.beforeSwap.selector, returnDelta, 5000 | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        PoolId poolId = key.toId();

        // take fee in fee currency if its the output currency
        uint256 feeAmount;
        if ((params.zeroForOne && key.currency1 == feeCurrency) || (!params.zeroForOne && key.currency0 == feeCurrency))
        {
            uint128 _amount = uint128(delta.amount1() < 0 ? -delta.amount1() : delta.amount1());
            feeAmount = uint256(_amount) * BURN_FEE_PERCENT / 100_00;
            poolManager.take(feeCurrency, address(this), feeAmount);

            // increment pool info
            poolInfo[poolId].accumulatedFees += feeAmount;
            poolInfo[poolId].swapCount++;
        }

        return (BaseHook.afterSwap.selector, int128(int256(feeAmount)));
    }

    /// @notice Uses accumulated fees to buyback and burn the paired token
    function buybackAndBurn(PoolKey calldata key, uint128 amountOutMinimum) external {
        PoolId poolId = key.toId();
        require(poolInfo[poolId].swapCount >= swapThreshold, "Not enough swaps");

        uint128 accumulatedFees = uint128(poolInfo[poolId].accumulatedFees);
        poolInfo[poolId].swapCount = 0;
        poolInfo[poolId].accumulatedFees = 0;

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        bool zeroForOne = feeCurrency == key.currency0;
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: zeroForOne,
                amountIn: accumulatedFees,
                amountOutMinimum: amountOutMinimum,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(zeroForOne ? key.currency0 : key.currency1, accumulatedFees);
        params[2] = abi.encode(zeroForOne ? key.currency1 : key.currency0, amountOutMinimum);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        swapRouter.execute(commands, inputs, block.timestamp + 999);

        // Burn output
        IERC20 token = IERC20(zeroForOne ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0));
        uint256 amountOut = token.balanceOf(address(this));
        token.transfer(address(0), amountOut);

        emit Burn(poolId, accumulatedFees, amountOut);
    }
}
