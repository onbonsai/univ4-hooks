// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256 balance);
    
    // Other ERC721 functions can be added here if needed
    // For this specific use case, we only need balanceOf
}