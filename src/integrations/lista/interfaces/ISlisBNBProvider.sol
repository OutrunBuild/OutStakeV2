//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface ISlisBNBProvider {
    /**
     * @notice Provides slisBNB to the upstream provider for a delegatee.
     * @dev The provider manages the delegated representation tied to `delegateTo`.
     * @param amount The amount of slisBNB to provide.
     * @param delegateTo The delegatee that should receive the delegated position.
     * @return The amount accounted for by the provider.
     */
    function provide(uint256 amount, address delegateTo) external returns (uint256);

    /**
     * @notice Releases previously provided slisBNB to a recipient.
     * @dev The provider unwinds the delegated position for the released amount.
     * @param recipient The address receiving the released tokens.
     * @param amount The amount of slisBNB to release.
     * @return The amount released to `recipient`.
     */
    function release(address recipient, uint256 amount) external returns (uint256);
}
