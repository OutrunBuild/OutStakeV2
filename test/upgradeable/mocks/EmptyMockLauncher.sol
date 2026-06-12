// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

/// @dev Minimal contract used as a placeholder launcher address for OutrunRouter tests.
/// OutrunRouter requires memeverseLauncher to have code, so a plain address won't work.
contract EmptyMockLauncher {}
