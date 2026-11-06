// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {OdometerArt} from "../src/art/OdometerArt.sol";
import {ISqueekCore} from "../src/interfaces/ISqueek.sol";
import {Reading} from "../src/Types.sol";
import {OdometerTestBase} from "./helpers/OdometerTestBase.sol";

/// @notice Regression tests for the independent review's findings (docs/REVIEW.md): the read boundary now checks
/// every copied word against the type its field declares, and the renderer is total over the uint64 work domain.
contract OdometerReviewFindingsTest is OdometerTestBase {
    uint256 internal constant U64 = type(uint64).max;

    function _state(uint256 settled, uint256 work, uint256 units, uint256 height) internal {
        vm.mockCall(address(core), abi.encodeCall(ISqueekCore.state, ()), abi.encode(settled, work, units, height));
    }

    function _page(uint256 offset, uint256 startWork, uint256 endWork) internal {
        vm.mockCall(
            address(core),
            abi.encodeWithSelector(ISqueekCore.roundPage.selector),
            abi.encode(offset, uint256(10), startWork, uint256(0), uint256(0), endWork)
        );
    }

    // ---- reading() and tokenURI() degrade to unknown on a non-canonical state() answer

    function test_oversizedWorkWordDegradesToUnknownInsteadOfPanicking() public {
        _mint(alice);
        _state(0, type(uint256).max, 0, 1);
        Reading memory r = odo.reading(1);
        assertFalse(r.live);
        assertEq(r.status, odo.UNKNOWN());
        assertEq(r.distanceMm, 0);
        assertEq(r.stage, 0);
        assertEq(r.startWork, 11_048);
        _assertMetadata(1);
        assertEq(vm.parseJsonString(_json(1), ".attributes[2].value"), "Unknown");
        assertEq(odo.ownerOf(1), alice);
    }

    function test_everyUint64FieldOfStateIsRangeChecked() public {
        _mint(alice);
        _state(U64 + 1, 12_048, 0, 1);
        assertFalse(odo.reading(1).live, "settledThroughRound");
        _state(0, U64 + 1, 0, 1);
        assertFalse(odo.reading(1).live, "cumulativeWork");
        _state(0, 12_048, 0, U64 + 1);
        assertFalse(odo.reading(1).live, "blockHeight");
        // cumulativeBlockUnits is uint96 and unused: it is not checked against uint64
        _state(0, 12_048, type(uint256).max, 1);
        assertTrue(odo.reading(1).live);
        assertEq(odo.reading(1).distanceMm, 887_000);
    }

    function test_largestCanonicalWordsAreStillLive() public {
        _mint(alice);
        _state(U64, U64, 0, U64);
        _page(0x20, U64 - 1, U64);
        Reading memory r = odo.reading(1);
        assertTrue(r.live);
        assertEq(r.work, U64 - 11_048);
        assertEq(r.distanceMm, (U64 - 11_048) * 887);
        assertEq(r.blockHeight, U64);
        assertEq(r.status, odo.JOGGING());
        assertEq(r.pace, 1);
        _assertMetadata(1);
    }

    function testFuzz_noStateAnswerCanMakeReadingRevert(uint256 w0, uint256 w1, uint256 w2, uint256 w3) public {
        _mint(alice);
        _state(w0, w1, w2, w3);
        Reading memory r = odo.reading(1);
        bool canonical = w0 <= U64 && w1 <= U64 && w3 <= U64;
        assertEq(r.live, canonical);
        assertEq(r.distanceMm, canonical && w1 > 11_048 ? (w1 - 11_048) * 887 : 0);
        _assertMetadata(1);
    }

    // ---- mint() refuses a baseline no canonical reading could ever exceed

    function test_mintRejectsNoncanonicalBaselineAndKeepsEligibility() public {
        _state(0, U64 + 1, 0, 1);
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
        _state(U64 + 1, 42, 0, 1);
        vm.prank(alice);
        vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
        assertEq(odo.totalMinted(), 0);
        assertEq(odo.idOf(alice), 0);
        assertEq(odo.balanceOf(alice), 0);
        _state(0, U64, 0, 1);
        assertEq(_mint(alice), 1, "the largest canonical word is a valid baseline");
        assertEq(odo.startWork(1), U64);
        assertEq(odo.reading(1).distanceMm, 0);
        _assertMetadata(1);
    }

    function testFuzz_mintStoresOnlyCanonicalBaselines(uint256 settled, uint256 work) public {
        _state(settled, work, 0, 1);
        bool canonical = settled <= U64 && work <= U64;
        vm.prank(alice);
        if (!canonical) vm.expectRevert(SqueekOdometer.CoreUnreadable.selector);
        odo.mint();
        assertEq(odo.totalMinted(), canonical ? 1 : 0);
        assertEq(odo.idOf(alice), canonical ? 1 : 0);
        if (canonical) assertEq(odo.startWork(1), work);
    }

    // ---- _status checks the page's offset and its uint64 work words

    function test_roundPageOutOfRangeWordsOrWrongOffsetGiveUnknown() public {
        _mint(alice);
        core.set(10, 12_048, 1_200);
        _page(0x20, 500, 2_000);
        assertEq(odo.reading(1).status, odo.ZOOMIES());
        _page(0x20, U64 + 1, 2_000);
        Reading memory r = odo.reading(1);
        assertEq(r.status, odo.UNKNOWN(), "start work out of range");
        assertEq(r.pace, 0);
        assertTrue(r.live, "the distance stays live");
        assertEq(r.distanceMm, 887_000);
        _page(0x20, 500, type(uint256).max);
        assertEq(odo.reading(1).status, odo.UNKNOWN(), "end work out of range");
        _page(0x40, 500, 2_000);
        assertEq(odo.reading(1).status, odo.UNKNOWN(), "a page that does not start at offset 0x20 is not a page");
        _page(0, 500, 2_000);
        assertEq(odo.reading(1).status, odo.UNKNOWN());
        _assertMetadata(1);
    }

    // ---- the renderer is total: the screen pegs at 9,999,999 km, the JSON keeps the exact distance

    function test_tenMillionKmRendersWithAPeggedScreenAndExactJson() public {
        core.set(0, 0, 0);
        _mint(alice);
        uint64 firstEightDigitWork = 11_273_957_159; // 10,000,000,000,033 mm
        core.set(0, firstEightDigitWork - 1, 1);
        _assertMetadata(1);
        core.set(0, firstEightDigitWork, 1);
        assertEq(odo.reading(1).distanceMm, uint256(firstEightDigitWork) * 887);
        _assertMetadata(1);
        assertEq(vm.parseJsonUint(_json(1), ".attributes[0].value"), 10_000_000);
        core.set(0, type(uint64).max, 1);
        _assertMetadata(1);
        assertEq(vm.parseJsonUint(_json(1), ".attributes[0].value"), uint256(type(uint64).max) * 887 / 1_000_000);
    }

    function test_screenPegsAtFiveNines() public pure {
        Reading memory r = _reading(OdometerArt.MAX_SHOWN_MM);
        bytes memory pegged = OdometerArt.svg(1, r);
        r.distanceMm = OdometerArt.MAX_SHOWN_MM + 1;
        assertEq(OdometerArt.svg(1, r), pegged, "one millimetre past the peg draws the same screen");
        r.distanceMm = uint256(type(uint64).max) * 887;
        assertEq(OdometerArt.svg(1, r), pegged, "the largest canonical distance draws the same screen");
        r.distanceMm = OdometerArt.MAX_SHOWN_MM - 1_000_000;
        assertNotEq(OdometerArt.svg(1, r), pegged, "below the peg the screen still counts");
    }

    // ---- the digits sit on the screen (columns 9..30), flush right, for every distance and for "?"

    function test_digitsStayOnTheScreenAndEndFlushRight() public pure {
        uint256[6] memory mm = [uint256(0), 420_000, 100_000_380, 999_990_000, 1_000_000_000, OdometerArt.MAX_SHOWN_MM];
        for (uint256 i; i < mm.length; i++) {
            (uint256 first, uint256 last) = _digitColumns(OdometerArt.svg(1, _reading(mm[i])));
            assertGe(first, 9, "a digit on the bezel");
            assertEq(last, 29, "the last lit column leaves the screen's last column as margin");
        }
        // the widest text fills the screen exactly: "100.00" starts on its first column
        (uint256 f, uint256 l) = _digitColumns(OdometerArt.svg(1, _reading(100_000_380)));
        assertEq(f, 9);
        assertEq(l, 29);
        Reading memory unknown = _reading(0);
        unknown.live = false;
        (f, l) = _digitColumns(OdometerArt.svg(1, unknown));
        assertGe(f, 9);
        assertEq(l, 29);
    }

    function testFuzz_digitsAlwaysOnTheScreen(uint64 work, uint8 display) public pure {
        Reading memory r = _reading(uint256(work) * 887);
        r.display = 0; // the LCD path is the one parsed; every display shares the same origin
        (uint256 first, uint256 last) = _digitColumns(OdometerArt.svg(uint256(display) + 1, r));
        assertGe(first, 9);
        assertEq(last, 29);
    }

    function _reading(uint256 mm) internal pure returns (Reading memory r) {
        r.live = true;
        r.status = OdometerArt.JOGGING;
        r.pace = 600;
        r.distanceMm = mm;
        r.stage = mm >= 100_000_000 ? 6 : 0;
    }

    /// @dev The first and last column lit by the LCD digit path, parsed from its runs "M{x} {y}.5h{len}".
    function _digitColumns(bytes memory svg) internal pure returns (uint256 first, uint256 last) {
        bytes memory open = bytes('<path stroke="#1d2b1d" d="');
        uint256 i = _find(svg, open) + open.length;
        first = type(uint256).max;
        while (svg[i] == "M") {
            i++;
            (uint256 x, uint256 j) = _number(svg, i);
            // skip " y.5h"
            j = _find(svg, bytes("h"), j) + 1;
            (uint256 len, uint256 k) = _number(svg, j);
            if (x < first) first = x;
            if (x + len - 1 > last) last = x + len - 1;
            i = k;
        }
        assertEq(svg[i], bytes1('"'), "digit path ends after its last run");
        assertTrue(first != type(uint256).max, "no digit run");
    }

    function _number(bytes memory s, uint256 i) internal pure returns (uint256 n, uint256 next) {
        while (s[i] >= "0" && s[i] <= "9") {
            n = n * 10 + (uint8(s[i]) - 48);
            i++;
        }
        next = i;
    }

    function _find(bytes memory hay, bytes memory needle) internal pure returns (uint256) {
        return _find(hay, needle, 0);
    }

    function _find(bytes memory hay, bytes memory needle, uint256 from) internal pure returns (uint256) {
        for (uint256 i = from; i + needle.length <= hay.length; i++) {
            bool hit = true;
            for (uint256 k; k < needle.length && hit; k++) {
                hit = hay[i + k] == needle[k];
            }
            if (hit) return i;
        }
        revert("needle not found");
    }
}
