// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OdometerTestBase} from "./helpers/OdometerTestBase.sol";
import {Reading} from "../src/Types.sol";

contract OdometerPropertiesTest is OdometerTestBase {
    function testFuzz_fullUint64DistanceDomain(uint64 baseline, uint64 current, uint64 height) public {
        core.set(0, baseline, 1);
        _mint(alice);
        core.set(0, current, height);
        Reading memory r = odo.reading(1);
        uint256 delta = current > baseline ? uint256(current) - baseline : 0;
        assertEq(r.work, delta);
        assertEq(r.startWork, baseline);
        assertEq(r.distanceMm, delta * 887);
        assertEq(r.blockHeight, height);
        assertTrue(r.live);
        assertLe(r.stage, 6);
        assertLt(r.display, 6);
        assertLt(r.casing, 4);
        assertLt(r.pouch, 5);
    }

    function testFuzz_stageMatchesIndependentThresholdCount(uint256 mm) public view {
        uint8 expected;
        if (mm >= 1_000_000) expected++;
        if (mm >= 5_000_000) expected++;
        if (mm >= 10_000_000) expected++;
        if (mm >= 25_000_000) expected++;
        if (mm >= 50_000_000) expected++;
        if (mm >= 100_000_000) expected++;
        assertEq(odo.stageOf(mm), expected);
    }

    function test_exactStageBoundaries() public view {
        uint256[6] memory mm = [uint256(1_000_000), 5_000_000, 10_000_000, 25_000_000, 50_000_000, 100_000_000];
        for (uint8 i; i < mm.length; ++i) {
            assertEq(odo.stageOf(mm[i] - 1), i);
            assertEq(odo.stageOf(mm[i]), i + 1);
            assertEq(odo.stageOf(mm[i] + 1), i + 1);
        }
    }

    function testFuzz_metadataIsDecodableOverTheWholeWorkDomain(uint64 start, uint64 extra, uint16 pace, uint8 tier)
        public
    {
        // Every uint64 work delta renders: the screen pegs at 9,999,999 km and the JSON keeps the exact figure.
        // Keep total work >= recent round work so the typed mock has a valid ledger history.
        uint64 work = uint64(bound(extra, 0, type(uint64).max - pace));
        start = uint64(bound(start, pace, type(uint64).max - work));
        core.set(0, start, 1);
        _mint(alice);
        core.set(10, start + work, 1_200);
        core.setRound(10, pace);
        uint256[5] memory powers = [uint256(0), 1, 4_840e18, 23_426e18, 113_380e18];
        tier = uint8(bound(tier, 0, 4));
        staking.setPower(alice, powers[tier]);
        _assertMetadata(1);
        string memory json = _json(1);
        assertEq(vm.parseJsonUint(json, ".attributes[9].value"), start);
        assertEq(vm.parseJsonUint(json, ".attributes[8].value"), pace);
        assertEq(vm.parseJsonString(json, ".attributes[6].value"), tier == 0 ? "No" : "Yes");
        assertEq(
            vm.parseJsonString(json, ".attributes[2].value"),
            pace == 0 ? "Napping" : pace < 1_500 ? "Jogging" : "Zoomies"
        );
    }

    function test_recoveredCoreRestoresLiveMetadataWithoutRefresh() public {
        _mint(alice);
        core.setBroken(true);
        string memory unknown = _json(1);
        assertEq(vm.parseJsonString(unknown, ".attributes[2].value"), "Unknown");
        assertEq(vm.parseJsonUint(unknown, ".attributes[9].value"), 11_048);
        core.setBroken(false);
        core.set(10, 13_048, 1_300);
        core.setRound(10, 1_500);
        string memory live = _json(1);
        assertEq(vm.parseJsonString(live, ".attributes[1].value"), "Warm-up");
        assertEq(vm.parseJsonString(live, ".attributes[2].value"), "Zoomies");
        assertEq(vm.parseJsonUint(live, ".attributes[8].value"), 1_500);
        assertNotEq(keccak256(bytes(unknown)), keccak256(bytes(live)));
        assertEq(odo.startWork(1), 11_048);
    }
}
