// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {
    /// @dev populated with default anvil addresses
    IERC20 constant weth = IERC20(address(0x1d3C6386F05ed330c1a53A31Bb11d410AeD094dF)); // weth
    // IERC20 constant token1 = IERC20(address(0x1d3C6386F05ed330c1a53A31Bb11d410AeD094dF)); // weth
    // IERC20 constant token0 = IERC20(address(0x036CbD53842c5426634e7929541eC2318f3dCF7e)); // usdc?
    IERC20 constant token0 = IERC20(address(0x3d2bD0e15829AA5C362a4144FdF4A1112fa29B5c)); // bonsai
    // IERC20 constant token1 = IERC20(address(0x1a87a3040aA286e904489D630AAa63A22ac2f9Cd)); // zoomer
    IERC20 constant token1 = IERC20(address(0xF29de9d3ADbE0392595A47eC62cBC13dF304d57B)); // NRG2
    // IHooks constant hookContract = IHooks(0xCED5Aa78A6568597883336E575FbA83D8750c080); // default hook, base sepolia
    // IHooks constant hookContract = IHooks(address(0x0)); 
    IHooks constant hookContract = IHooks(address(0xA788031C591B6824c032a0EFe74837EE5eaeC080)); 

    Currency constant currency0 = Currency.wrap(address(token0));
    Currency constant currency1 = Currency.wrap(address(token1));
}
