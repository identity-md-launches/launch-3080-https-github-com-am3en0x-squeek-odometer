// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {OdometerArt} from "../src/art/OdometerArt.sol";
import {SqueekOdometer} from "../src/SqueekOdometer.sol";
import {Reading} from "../src/Types.sol";
import {MockCore, MockNFT, MockStaking} from "./mocks/Mocks.sol";

contract ArtHarness {
    function svg(Reading memory r) external pure returns (string memory) {
        return string(OdometerArt.svg(1, r));
    }

    function svgId(uint256 id, Reading memory r) external pure returns (string memory) {
        return string(OdometerArt.svg(id, r));
    }

    function json(uint256 id, Reading memory r) external pure returns (string memory) {
        return string(OdometerArt.json(id, r));
    }

    function km(uint256 mm) external pure returns (string memory) {
        return string(OdometerArt.kmText(mm));
    }

    function display(uint256 roll) external pure returns (uint8) {
        return OdometerArt.displayOf(roll);
    }

    function casing(uint256 roll) external pure returns (uint8) {
        return OdometerArt.casingOf(roll);
    }

    function pouch(uint256 roll) external pure returns (uint8) {
        return OdometerArt.pouchOf(roll);
    }
}

contract OdometerArtTest is Test {
    ArtHarness art = new ArtHarness();

    // stage, status (0 napping, 1 jogging, 2 zoomies, 3 unknown), distance; plain traits, no holder
    function _r(uint8 stage, uint8 status, uint256 mm) internal pure returns (Reading memory r) {
        r.stage = stage;
        r.status = status;
        r.distanceMm = mm;
        r.work = mm / 887;
        r.startWork = 11_048;
        r.blockHeight = 1_140;
        r.live = status != 3;
        r.pace = status == 2 ? 1_800 : status == 1 ? 600 : 0;
    }

    function _has(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i + n.length <= h.length; i++) {
            bool ok = true;
            for (uint256 j; j < n.length; j++) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    // ---- the document

    function test_svgIsAWholeDocumentWithTheDotGrid() public view {
        string memory s = art.svg(_r(2, 1, 5_310_000));
        assertTrue(_has(s, '<svg xmlns="http://www.w3.org/2000/svg" viewBox="4 8 32 32"'), "framed close on him");
        assertTrue(_has(s, 'fill="url(#g)"'), "the dot grid");
        bytes memory b = bytes(s);
        assertEq(
            string(
                abi.encodePacked(
                    b[b.length - 6], b[b.length - 5], b[b.length - 4], b[b.length - 3], b[b.length - 2], b[b.length - 1]
                )
            ),
            "</svg>"
        );
    }

    // ---- napping and running

    function test_napIsNightOnBeddingWithAStillWheel() public view {
        string memory nap = art.svg(_r(2, 0, 5_000_000));
        assertTrue(_has(nap, 'fill="#0b0b0d" opacity=".45"'), "night falls");
        assertTrue(_has(nap, "#f1f0ff"), "stars");
        assertTrue(_has(nap, "#b9925a"), "bedding");
        assertFalse(_has(nap, 'values="1;0'), "nothing spins");
        assertTrue(_has(nap, '<animateTransform attributeName="transform" type="translate"'), "but his z float");
        string memory jog = art.svg(_r(2, 1, 5_000_000));
        assertFalse(_has(jog, "#0b0b0d"));
        assertFalse(_has(jog, "#b9925a"));
    }

    function test_theWheelAndLegsRunAtHisPace() public view {
        // pace 600: a spin of 900 - 600/3 = 700 ms, steps two thirds of it; pace 1,800: 300 ms and 200 ms
        string memory jog = art.svg(_r(2, 1, 5_000_000));
        assertTrue(
            _has(
                jog,
                '<animate attributeName="opacity" values="1;0;0" dur="700ms" calcMode="discrete" repeatCount="indefinite"/>'
            ),
            "a three-frame spin"
        );
        assertTrue(_has(jog, 'values="0;0;1"'));
        assertTrue(_has(jog, 'dur="466ms"'));
        string memory zoom = art.svg(_r(2, 2, 5_000_000));
        assertTrue(_has(zoom, 'dur="300ms"'));
        assertTrue(_has(zoom, 'dur="200ms"'));
        assertTrue(_has(zoom, "#e8dcc8"), "dust at his feet");
        assertFalse(_has(jog, "#e8dcc8"));
        Reading memory flat = _r(2, 2, 5_000_000);
        flat.pace = 10_000;
        assertTrue(_has(art.svg(flat), 'dur="240ms"'), "never faster than 240 ms");
    }

    // ---- stage: the wheel's metal and one piece of gear

    function test_theWheelUpgradesWithTheStage() public view {
        assertTrue(_has(art.svg(_r(0, 1, 0)), "#9aa3b5"), "steel");
        assertTrue(_has(art.svg(_r(3, 1, 10_400_000)), "#b9773f"), "bronze from Runner");
        assertTrue(_has(art.svg(_r(5, 1, 50_400_000)), "#c4ccd8"), "silver for a Marathoner");
        assertTrue(_has(art.svg(_r(6, 1, 100_400_000)), "#e0b23a"), "gold for a Legend");
        assertFalse(_has(art.svg(_r(0, 1, 0)), "#e0b23a"));
    }

    function test_onePieceOfGearPerStage() public view {
        assertFalse(_has(art.svg(_r(0, 1, 0)), "#d64545"), "a Newbie wears nothing");
        assertTrue(_has(art.svg(_r(2, 1, 5_400_000)), "#d64545"), "a Jogger's headband");
        assertTrue(_has(art.svg(_r(3, 1, 10_400_000)), "#4a74c9"), "a Runner's shoes");
        assertFalse(_has(art.svg(_r(4, 1, 25_400_000)), "#4a74c9"), "taken off for the bib");
        assertTrue(_has(art.svg(_r(4, 1, 25_400_000)), "#d64545"), "the bib's number");
        assertTrue(_has(art.svg(_r(5, 1, 50_400_000)), "#ffe089"), "a Marathoner's medal");
        string memory legend = art.svg(_r(6, 1, 100_400_000));
        assertTrue(_has(legend, "#fff3c4"), "the crown");
        assertTrue(_has(legend, "#7d55c7"), "the cape");
        string memory legendNap = art.svg(_r(6, 0, 100_400_000));
        assertTrue(_has(legendNap, "#fff3c4"), "he sleeps in his crown");
        assertFalse(_has(legendNap, "#7d55c7"));
    }

    function test_theRacersBibCarriesTheTokensLastDigit() public view {
        // a 7 starts with a full top row: the bib's digit at (13, 22)
        assertTrue(_has(art.svgId(47, _r(4, 1, 25_400_000)), '<path stroke="#d64545" d="M13 22.5h3'));
    }

    function test_confettiFalls() public view {
        assertTrue(_has(art.svg(_r(1, 1, 1_100_000)), 'values="0 0;0 1;0 2"'));
    }

    function test_confettiRightAfterANewStage() public view {
        assertTrue(_has(art.svg(_r(1, 1, 1_100_000)), "#d64545"), "100 m into Warm-up");
        assertFalse(_has(art.svg(_r(1, 1, 1_400_000)), "#d64545"), "gone after 300 m");
    }

    function test_pipsPastTheLastStage() public view {
        // on a steel wheel nothing else is light gold: the pips are the only #ffe089
        assertFalse(_has(art.svg(_r(0, 1, 150_000_000)), "#ffe089"));
        assertTrue(_has(art.svg(_r(0, 1, 250_000_000)), "#ffe089"), "one pip at 200 km");
    }

    // ---- the token's own odometer and the holder's bottle

    function test_bottleByHolderTier() public view {
        Reading memory r = _r(0, 1, 0);
        assertFalse(_has(art.svg(r), "#cfe8f5"), "no bottle without a Squeek");
        r.tier = 1;
        r.holder = true;
        assertTrue(_has(art.svg(r), "#cfe8f5"));
        assertTrue(_has(art.svg(r), "#a9dcf5"), "the water is water");
        assertTrue(_has(art.svg(r), "#b9773f"), "a bronze cap");
        r.tier = 4;
        assertTrue(_has(art.svg(r), "#7fe7ff"), "a diamond cap");
    }

    function test_displayCasingAndPouch() public view {
        Reading memory r = _r(0, 1, 420_000);
        assertTrue(_has(art.svg(r), 'fill="#9fb58a"'), "an LCD: dark digits on grey-green");
        assertTrue(_has(art.svg(r), '<path stroke="#1d2b1d"'));
        r.display = 1;
        assertTrue(_has(art.svg(r), '<path stroke="#ffb000"'), "amber digits");
        r.display = 2;
        assertTrue(_has(art.svg(r), 'stroke-linecap="round"'), "LED digits are round dots");
        assertTrue(_has(art.svg(r), ".5h.2"));
        r.display = 3;
        assertTrue(_has(art.svg(r), 'fill="url(#v)"'), "a VFD over its dot grid");
        r.display = 4;
        assertTrue(_has(art.svg(r), '<path stroke="#5a2810" stroke-width="3"'), "nixie digits glow");
        r.display = 5;
        string memory mech = art.svg(r);
        assertTrue(_has(mech, 'fill="#ece6d6"'), "a light mechanical counter");
        assertTrue(_has(mech, '<path stroke="#c0392b"'), "its last digit in red");
        assertTrue(
            _has(mech, '<rect x="8" y="34" width="24" height="5" fill="#8f8268"/>'),
            "a bezel keeps the screen off the casing"
        );
        r.casing = 3;
        assertTrue(_has(art.svg(r), "#e8823a"), "signal orange casing");
        assertFalse(_has(art.svg(r), "#d6334a"));
        r.pouch = 2;
        assertTrue(_has(art.svg(r), "#d6334a"), "a berry in his paws");
        assertTrue(_has(art.svg(r), "#3fa34d"), "with its leaf");
    }

    function test_rollsHaveTheirRarities() public view {
        assertEq(art.display(0), 0);
        assertEq(art.display(29), 0);
        assertEq(art.display(30), 1);
        assertEq(art.display(96), 4);
        assertEq(art.display(97), 5);
        assertEq(art.display(99), 5);
        assertEq(art.casing(34), 0);
        assertEq(art.casing(35), 1);
        assertEq(art.casing(65), 2);
        assertEq(art.casing(90), 3);
        assertEq(art.pouch(44), 0);
        assertEq(art.pouch(45), 1);
        assertEq(art.pouch(89), 2);
        assertEq(art.pouch(97), 3);
        assertEq(art.pouch(98), 4);
        assertEq(art.pouch(99), 4);
    }

    // ---- text and metadata

    function test_kmText() public view {
        assertEq(art.km(0), "0.00");
        assertEq(art.km(999_999), "0.99");
        assertEq(art.km(12_730_000), "12.73");
        assertEq(art.km(104_660_000), "104.66");
        assertEq(art.km(1_234_500_000), "1234", "whole km from 1,000");
    }

    function test_jsonHasTheTraits() public view {
        Reading memory r = _r(3, 2, 12_730_000);
        (r.display, r.casing, r.pouch, r.tier, r.holder) = (4, 2, 3, 4, true);
        string memory j = art.json(42, r);
        assertTrue(_has(j, '"name":"Squeek Odometer #42"'));
        assertTrue(_has(j, '"image":"data:image/svg+xml;base64,'));
        assertTrue(_has(j, '{"trait_type":"Distance (km)","display_type":"number","value":12.73}'));
        assertTrue(_has(j, '{"trait_type":"Stage","value":"Runner"}'));
        assertTrue(_has(j, '{"trait_type":"Status","value":"Zoomies"}'));
        assertTrue(_has(j, '{"trait_type":"Display","value":"Nixie"}'));
        assertTrue(_has(j, '{"trait_type":"Casing","value":"Charcoal"}'));
        assertTrue(_has(j, '{"trait_type":"Treat","value":"Coin"}'));
        assertTrue(_has(j, '{"trait_type":"Water Bottle","value":"Diamond"}'));
        assertTrue(_has(j, '{"trait_type":"Pace (turns / 30 min)","display_type":"number","value":1800}'));
        assertTrue(_has(j, '{"trait_type":"Start Work","display_type":"number","value":11048}'));
        bytes memory b = bytes(j);
        int256 depth;
        for (uint256 i; i < b.length; i++) {
            if (b[i] == "{" || b[i] == "[") depth++;
            if (b[i] == "}" || b[i] == "]") depth--;
            assertGe(depth, 0);
        }
        assertEq(depth, 0);
    }

    function test_unknownReadsAsUnknown() public view {
        assertTrue(_has(art.json(1, _r(0, 3, 0)), '{"trait_type":"Status","value":"Unknown"}'));
        assertTrue(_has(art.svg(_r(0, 3, 0)), 'fill="#9fb58a"'), "the screen still draws");
    }

    // ---- through the contract

    function _odo() internal returns (MockCore core, SqueekOdometer odo) {
        core = new MockCore();
        core.set(10, 11_048, 1_140);
        odo = new SqueekOdometer(address(core), address(new MockNFT()), address(new MockStaking()));
        vm.prank(address(0xA11CE));
        odo.mint();
    }

    function test_tokenUriOnTheContract() public {
        (MockCore core, SqueekOdometer odo) = _odo();
        assertTrue(_has(odo.tokenURI(1), "data:application/json;base64,"));
        core.setBroken(true);
        assertTrue(_has(odo.tokenURI(1), "data:application/json;base64,"), "a broken core does not break the token");
        vm.expectRevert();
        odo.tokenURI(2);
        assertTrue(odo.supportsInterface(0x49064906), "ERC-4906");
        assertTrue(odo.supportsInterface(0x80ac58cd), "ERC-721");
    }

    function test_theContractRollsTheOdometerFromIdAndStart() public {
        (, SqueekOdometer odo) = _odo();
        uint256 h = uint256(keccak256(abi.encode(uint256(1), uint256(11_048))));
        Reading memory r = odo.reading(1);
        assertEq(r.display, art.display(h % 100));
        assertEq(r.casing, art.casing((h >> 64) % 100));
        assertEq(r.pouch, art.pouch((h >> 128) % 100));
    }

    function test_tokenUriGasIsModest() public {
        (MockCore core, SqueekOdometer odo) = _odo();
        core.set(40, 400_000, 9_500);
        core.setRound(40, 2_000);
        uint256 g = gasleft();
        odo.tokenURI(1);
        assertLt(g - gasleft(), 20_000_000, "an eth_call must stay far below node limits");
    }
}
