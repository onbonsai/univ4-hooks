// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/// @notice Shared configuration between scripts
contract Config {
    /// @dev populated with default anvil addresses
    IERC20 weth = IERC20(address(0x1d3C6386F05ed330c1a53A31Bb11d410AeD094dF)); // weth
    // IERC20 token1 = IERC20(address(0x1d3C6386F05ed330c1a53A31Bb11d410AeD094dF)); // weth
    // IERC20 token0 = IERC20(address(0x036CbD53842c5426634e7929541eC2318f3dCF7e)); // usdc?
    IERC20 token0 = IERC20(address(0x3d2bD0e15829AA5C362a4144FdF4A1112fa29B5c)); // bonsai
    // IERC20 token1 = IERC20(address(0x1a87a3040aA286e904489D630AAa63A22ac2f9Cd)); // zoomer
    // IERC20 token1 = IERC20(address(0xF29de9d3ADbE0392595A47eC62cBC13dF304d57B)); // NRG2
    IERC20 token1 = IERC20(address(0xf4587227797CC95CeB057dA02f87eB19284BEaC3)); // COFFEE
    // IHooks hookContract = IHooks(0xCED5Aa78A6568597883336E575FbA83D8750c080); // default hook, base sepolia
    // IHooks hookContract = IHooks(address(0x0));
    IHooks hookContract = IHooks(address(0x56464A8f627495cf7FDBd57Ef8dC5A853d14C080));

    Currency currency0 = Currency.wrap(address(token0));
    Currency currency1 = Currency.wrap(address(token1));
}
