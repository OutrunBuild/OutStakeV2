// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

contract ERC7201StorageLocationUpgradeableTest is Test {
    string[] internal ids;
    bytes32[] internal slots;

    function setUp() external {
        _add("outrun.storage.AutoIncrementId", 0xf89e69ccd0f0ce2bd1d8010b084ae175827f4bf65e4d8f8f0dcc892b62a15b00);
        _add("outrun.storage.OutrunERC20", 0x77d1373660b69e27ef6b7052ba58efede68bac459506eb86ffbe444e4aa4d100);
        _add("outrun.storage.OutrunUniversalAssets", 0x2b82e9d5002467e1c5131297c0670c5f52b39ef4cd7112616d88ce4844484100);
        _add("outrun.storage.OutrunRateLimiter", 0xd48bb12cf4270f606da51b56ba6371646e75d13e96dee8184b97a52adeda4000);
        _add("outrun.storage.OutrunStakingPosition", 0xd6ebf98633cd133425e2ec4f5c3d5a1e15a1a3a82505bb0f6ed101932bed5200);
        _add("outrun.storage.SYBase", 0x47ee1d05b1829703ec3dd61a22c784c3e0b2d5dbffb0a55782381dabc9c3eb00);
        _add("outrun.storage.OutrunL2StakedTokenSY", 0xc47406d15de2f1a441454f67ed7478fdea0ecc904b6c2e82cf019a344492a300);
        _add("outrun.storage.OutrunAaveV3SY", 0x72217a3ea688bfbd31b48bb32b412c4301717e3e5d9754c566b8b7af0c910a00);
        _add("outrun.storage.OutrunAsBNBSY", 0x037ff1f0c947b2628c5e451ad69209eea6dad0b9c31bcbf8186cb85263174300);
        _add("outrun.storage.OutrunStakedUSDeSY", 0xc6349914f41ee852ec6671cc14b058a0b3e3b25674e5c52708e581f58824ce00);
        _add("outrun.storage.OutrunWeETHSY", 0x7c889822051b104e8bf752526ae310e0de27a4e1749297b1b10b3e2ca8c5af00);
        _add(
            "outrun.storage.OutrunL2WrappableWstETHSY",
            0x9da4bc70408d68d126efeec83eb110f8384c649e456fbb92edf8e08a726b7a00
        );
        _add("outrun.storage.OutrunL2WstETHSY", 0x7e7baed09ce3e69f5f6da116459da34887eb64a288faa154ae38a8995cda0000);
        _add("outrun.storage.OutrunWstETHSY", 0x98c280cd6bacd9bd0502068e8dcfd5ea32813f0670f2ca30214fa4ffb7350000);
        _add("outrun.storage.OutrunSlisBNBSY", 0x7eac519ceef6d43eab45b04bb8d5ed66a747bcd5dc85b70bf40db56a58a1eb00);
        _add("outrun.storage.OutrunL2StakedUsdsSY", 0x87ae3998ef315b555888805db0bb7dcff6c26c66153e8971d42ff237c1174500);
        _add("outrun.storage.OutrunStakedUsdsSY", 0x74aedace728c226c8b576fb3084503c20ae3f009148ad8baca9527cdb56df900);
    }

    function testStorageLocationsUseERC7201NamespaceIds() external {
        for (uint256 i; i < ids.length; ++i) {
            assertEq(slots[i], _erc7201(ids[i]), ids[i]);
        }
    }

    function _add(string memory id, bytes32 slot) internal {
        ids.push(id);
        slots.push(slot);
    }

    function _erc7201(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }
}
