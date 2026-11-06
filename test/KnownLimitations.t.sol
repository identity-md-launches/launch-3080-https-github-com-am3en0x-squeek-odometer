// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {ISqueekCore} from "../src/interfaces/ISqueek.sol";
import {OdometerTestBase} from "./helpers/OdometerTestBase.sol";

/// @notice Reproducers of the unchanged upstream's liveness defects, NOT assertions that these are desirable.
/// @dev See docs/REVIEW.md. Keeping contract and art unchanged is an explicit requirement of the imported brief.
contract OdometerKnownLimitationsTest is OdometerTestBase {
    function test_knownLimitation_oversizedWorkWordPanicsOnReadingAndURI() public {
        _mint(alice);
        // _read validates length only. This word is not a canonical ABI-encoded uint64.
        vm.mockCall(
            address(core),
            abi.encodeCall(ISqueekCore.state, ()),
            abi.encode(uint256(0), type(uint256).max, uint256(0), uint256(1))
        );
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        odo.reading(1);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        odo.tokenURI(1);
        assertEq(odo.ownerOf(1), alice, "ownership and transfers are unaffected");
    }

    function test_knownLimitation_largeCanonicalWorkOverflowsDisplayWidth() public {
        core.set(0, 0, 0);
        _mint(alice);
        // Exactly the first work value reaching 10,000,000 km: eight digits * four pixels > x=30.
        uint64 firstBadWork = 11_273_957_159;
        core.set(0, firstBadWork - 1, 1);
        _assertMetadata(1);
        core.set(0, firstBadWork, 1);
        assertEq(odo.reading(1).distanceMm, uint256(firstBadWork) * 887);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        odo.tokenURI(1);
    }

    function test_knownLimitation_mintAcceptsNoncanonicalWorkPrefix() public {
        vm.mockCall(address(core), abi.encodeCall(ISqueekCore.state, ()), abi.encode(uint256(0), type(uint256).max));
        assertEq(_mint(alice), 1);
        assertEq(odo.startWork(1), type(uint256).max);
        vm.clearMockedCalls();
        core.set(0, type(uint64).max, 1);
        assertEq(odo.reading(1).distanceMm, 0, "canonical work can never catch this baseline");
        _assertMetadata(1);
    }
}
