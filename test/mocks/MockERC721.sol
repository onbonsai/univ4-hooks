// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC721} from "solmate/src/tokens/ERC721.sol";

contract MockERC721 is ERC721 {
    uint256 private _tokenIdCounter;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) public {
        _safeMint(to, tokenId);
        _tokenIdCounter++;
    }

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }
}
