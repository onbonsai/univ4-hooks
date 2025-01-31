// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "../interfaces/IERC721.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

/**
 * @title DefaultSettings
 * @author @c0rv0s
 * @notice Provides functions that need to be implemented in launchpad hooks
 */
contract DefaultSettings {
    IERC721 bonsaiNFT;

    constructor(address _bonsaiNFT) {
        bonsaiNFT = IERC721(_bonsaiNFT);
    }

    function beforeSwapFeeOverride() public view returns (uint24) {
        address user = tx.origin;

        if (user == address(0)) return 15000 | LPFeeLibrary.OVERRIDE_FEE_FLAG;

        // Get the balance of Bonsai NFTs in the user's wallet
        uint256 nftBalance = bonsaiNFT.balanceOf(user);

        if (nftBalance > 0) {
            return 0 | LPFeeLibrary.OVERRIDE_FEE_FLAG; // 0% fee if user has any NFTs
        } else {
            return 15000 | LPFeeLibrary.OVERRIDE_FEE_FLAG; // 1.5% fee if user has no NFTs
        }
    }
}
