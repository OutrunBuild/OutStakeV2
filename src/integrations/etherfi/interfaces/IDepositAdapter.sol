//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

interface IDepositAdapter {
    /**
     * @notice Deposits native ETH through Ether.fi and receives weETH.
     * @dev The adapter handles the upstream staking path and returns the wrapped output amount.
     * @param _referral The referral address passed to the upstream deposit adapter.
     * @return The amount of weETH minted for the deposit.
     */
    function depositETHForWeETH(address _referral) external payable returns (uint256);
}
