// SPDX-License-Identifier: MIT

/*                                   
                                                                       
    _/_/_/_/_/    _/_/_/  _/_/_/_/_/  _/_/_/      _/_/    _/_/_/_/_/   
         _/    _/            _/      _/    _/  _/    _/      _/        
      _/        _/_/        _/      _/_/_/    _/_/_/_/      _/         
   _/              _/      _/      _/    _/  _/    _/      _/          
_/_/_/_/_/  _/_/_/        _/      _/    _/  _/    _/      _/           
                                                                                                                          
                                                                       
*/

pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/**
 * @title Tax
 * @notice Applies a tax to the swap amount to be collected in quote token
 */
contract Tax is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;

    error InvalidTax();

    uint24 private constant _BPS = 100_00;

    Currency public quote;
    uint24 public buyTaxBps;
    uint24 public sellTaxBps;
    address public recipient;

    constructor(IPoolManager _poolManager, address _quote, uint24 _buyTax, uint24 _sellTax, address _recipient, address initialOwner)
        BaseHook(_poolManager)
        Ownable(initialOwner)
    {
        if (_buyTax > _BPS / 4 || _sellTax > _BPS / 4) revert InvalidTax(); // Max 25% tax
        quote = Currency.wrap(_quote);
        buyTaxBps = _buyTax;
        sellTaxBps = _sellTax;
        recipient = _recipient;
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
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Disallow exact-output swaps entirely with specific messages
        if (params.amountSpecified > 0) {
            bool outputIsQuote = (params.zeroForOne ? key.currency1 : key.currency0) == quote;
            if (outputIsQuote) {
                revert("exact output sell not allowed");
            } else {
                revert("exact output buy not allowed");
            }
        }

        if ((params.zeroForOne ? key.currency0 : key.currency1) == quote) {
            // exact in buy, tax on input (quote token)
            uint256 inputAbs = uint256(-params.amountSpecified);
            uint256 tax = (inputAbs * buyTaxBps) / _BPS;
            poolManager.take(quote, recipient, tax);
            return (BaseHook.beforeSwap.selector, toBeforeSwapDelta(int128(int256(tax)), 0), 0);
        }
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // Only handle exact-input sells (token -> quote): tax on quote output
        if (params.amountSpecified < 0 && (params.zeroForOne ? key.currency1 : key.currency0) == quote) {
            int128 outputDelta = params.zeroForOne ? delta.amount1() : delta.amount0();
            uint256 outputAbs = uint256(uint128(outputDelta)); // outputDelta should be positive
            uint256 tax = (outputAbs * sellTaxBps) / _BPS;
            poolManager.take(quote, recipient, tax);
            return (BaseHook.afterSwap.selector, int128(int256(tax)));
        }
        return (BaseHook.afterSwap.selector, 0);
    }

    /**
     * @notice Set the buy tax rate (only owner)
     * @param _buyTax New buy tax rate in basis points (max 2500 = 25%)
     */
    function setBuyTax(uint24 _buyTax) external onlyOwner {
        if (_buyTax > _BPS / 4) revert InvalidTax();
        buyTaxBps = _buyTax;
    }

    /**
     * @notice Set the sell tax rate (only owner)
     * @param _sellTax New sell tax rate in basis points (max 2500 = 25%)
     */
    function setSellTax(uint24 _sellTax) external onlyOwner {
        if (_sellTax > _BPS / 4) revert InvalidTax();
        sellTaxBps = _sellTax;
    }

    /**
     * @notice Set the tax recipient address (only owner)
     * @param _recipient New recipient address
     */
    function setRecipient(address _recipient) external onlyOwner {
        require(_recipient != address(0), "Invalid recipient");
        recipient = _recipient;
    }
}
