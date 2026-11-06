// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekOdometer} from "../../src/SqueekOdometer.sol";
import {ISqueekCore} from "../../src/interfaces/ISqueek.sol";
import {Reading} from "../../src/Types.sol";

/// @notice Against the real Squeekchain contracts on Sepolia: forge test --profile fork
/// (the RPC must serve state at the pinned block; pass --fork-url to use another one).
contract SqueekOdometerForkTest is Test {
    address constant CORE = 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4;
    address constant SQUEEKS = 0xC4C7982657f00509548F3a3a41db7FA439a6856B;
    address constant STAKING = 0x50fd1780526C3186A0c037c7622203bC4fb611ca;
    uint256 constant BLOCK = 12_077_300;

    function test_mintAndReadAgainstSepolia() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"), BLOCK);
        SqueekOdometer odo = new SqueekOdometer(CORE, SQUEEKS, STAKING);
        ISqueekCore.CoreState memory s = ISqueekCore(CORE).state();
        assertGt(s.cumulativeWork, 0, "the wheel has settled work");

        vm.prank(address(0xA11CE));
        uint256 id = odo.mint();
        assertEq(odo.startWork(id), s.cumulativeWork);

        Reading memory r = odo.reading(id);
        assertTrue(r.live, "SqueekCore answered");
        assertEq(r.work, 0, "nothing ran since the mint in the same block");
        assertEq(r.blockHeight, s.blockHeight);
        assertLt(r.status, 3, "napping, jogging or zoomies, not unknown");
        assertFalse(r.holder, "a fresh address holds no Squeek");

        string memory uri = odo.tokenURI(id);
        assertGt(bytes(uri).length, 1_000);
        emit log_named_string("status", r.status == 0 ? "napping" : r.status == 1 ? "jogging" : "zoomies");
        emit log_named_uint("settled work", s.cumulativeWork);
    }
}
