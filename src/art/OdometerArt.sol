// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Reading} from "../Types.sol";
import {Sprites} from "./Sprites.sol";

/// @title OdometerArt
/// @notice Renders a reading as an animated pixel SVG and as ERC-721 metadata JSON: Squeektoshi on his wheel, and the
/// token's odometer as the wheel's base. The scene is drawn on a 40x40 grid and framed through a 32x32 window, so the
/// wheel's top crops off and he fills the picture. Layers are run data from tools/sprites.py; each color group becomes
/// one SVG path of 1-pixel strokes. Motion is frame by frame (discrete SMIL) at his real pace, so pixels stay crisp; a
/// viewer without SMIL shows the first frame. Output goes into a buffer allocated once (linear gas).
library OdometerArt {
    using Strings for uint256;

    uint8 internal constant NAPPING = 0;
    uint8 internal constant JOGGING = 1;
    uint8 internal constant ZOOMIES = 2;
    /// @notice The largest distance the odometer's five-digit screen can show, 99,999 km; past it the screen pegs
    /// like a real odometer's, while the metadata keeps the exact figure.
    uint256 internal constant MAX_SHOWN_MM = 99_999_999_999;

    // palette slots recolored per token (see tools/sprites.py)
    uint8 private constant RIM_DARK = 10;
    uint8 private constant RIM = 11;
    uint8 private constant RIM_LIGHT = 12;
    uint8 private constant CAP = 28;

    /// @dev The recolored slots for one token: the wheel's metal by stage, the bottle's cap by holder tier.
    struct Look {
        bytes rimDark;
        bytes rim;
        bytes rimLight;
        bytes cap;
    }

    // ---------------------------------------------------------------- the picture

    function svg(uint256 id, Reading memory r) internal pure returns (bytes memory) {
        Buf memory b = _buf(32_768);
        Look memory look = _look(r);
        bool awake = r.status == JOGGING || r.status == ZOOMIES;
        bool zoom = r.status == ZOOMIES;
        string memory spin = _ms(_spinMs(r.pace));
        string memory step = _ms(_spinMs(r.pace) * 2 / 3);
        _add(
            b,
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="4 8 32 32" width="480" height="480" shape-rendering="crispEdges">'
        );
        _add(
            b,
            abi.encodePacked(
                '<rect width="40" height="40" fill="',
                _pick("#374559#2f5d62#4a6a3a#2e5a7a#6e2f4f#4b3f72#2a2346", r.stage),
                '"/>'
            )
        );
        // a faint dot grid, in the spirit of Squeekchain's dotted pixels; a dimmer one for a VFD screen
        _add(
            b,
            '<defs><pattern id="g" width="4" height="4" patternUnits="userSpaceOnUse"><rect x="2" y="2" width="1" height="1" fill="#fff" opacity=".09"/></pattern><pattern id="v" width="1" height="1" patternUnits="userSpaceOnUse"><rect width=".4" height=".4" fill="#14505c"/></pattern></defs><rect width="40" height="40" fill="url(#g)"/>'
        );

        // the wheel turns one way at his pace while he runs and stands still while he sleeps; a pip for every 100 km
        // past the first 100
        _layer(b, Sprites.RIM, look);
        if (awake) _frames3(b, Sprites.WHEEL_0, Sprites.WHEEL_1, Sprites.WHEEL_2, spin, look);
        else _layer(b, Sprites.WHEEL_0, look);
        _layer(b, Sprites.HUB, look);
        _pips(b, r.distanceMm);

        if (r.status == NAPPING) {
            _add(b, '<rect width="40" height="40" fill="#0b0b0d" opacity=".45"/>');
            _layer(b, Sprites.MOON, look);
            _layer(b, Sprites.STARS, look);
            _layer(b, Sprites.BEDDING, look);
        }
        if (r.tier > 0) _layer(b, Sprites.BOTTLE, look);
        if (zoom) _frames2(b, Sprites.DUST_0, Sprites.DUST_1, step, look);
        if (awake && r.stage == 6) _frames2(b, Sprites.CAPE_0, Sprites.CAPE_1, step, look);

        // Squeektoshi
        if (awake) {
            _layer(b, zoom ? Sprites.SQUEEK_ZOOM : Sprites.SQUEEK_RUN, look);
            // legs in two frames, with a Warm-up's wristband or a Runner's shoes on them
            bytes memory l0 = Sprites.LEGS_0;
            bytes memory l1 = Sprites.LEGS_1;
            if (r.stage == 1) (l0, l1) = (bytes.concat(l0, Sprites.WRIST_0), bytes.concat(l1, Sprites.WRIST_1));
            if (r.stage == 3) (l0, l1) = (bytes.concat(l0, Sprites.SHOES_0), bytes.concat(l1, Sprites.SHOES_1));
            _frames2(b, l0, l1, step, look);
        } else {
            _layer(b, Sprites.SQUEEK_NAP, look);
        }
        _treat(b, r.pouch, awake, look);
        _gear(b, id, r.stage, awake, step, look);
        if (r.status == NAPPING) {
            _add(
                b,
                '<g opacity=".6"><animateTransform attributeName="transform" type="translate" values="0 0;0 -1;0 -2" dur="2.4s" calcMode="discrete" repeatCount="indefinite"/>'
            );
            _layer(b, Sprites.ZZZ, look);
            _add(b, "</g>");
        }
        if (_justLevelled(r)) {
            _add(
                b,
                '<g><animateTransform attributeName="transform" type="translate" values="0 0;0 1;0 2" dur="1.2s" calcMode="discrete" repeatCount="indefinite"/>'
            );
            _layer(b, Sprites.CONFETTI, look);
            _add(b, "</g>");
        }

        _odometer(b, r);
        _add(b, "</svg>");
        return _done(b);
    }

    // ---------------------------------------------------------------- metadata

    function json(uint256 id, Reading memory r) internal pure returns (bytes memory) {
        bytes memory image = bytes(Base64.encode(svg(id, r)));
        Buf memory b = _buf(image.length + 2_560);
        _add(b, abi.encodePacked('{"name":"Squeek Odometer #', id.toString(), '",'));
        _add(
            b,
            '"description":"An odometer bolted to Squeektoshi\'s wheel. It counts how far the hamster has run since it was minted, read live from SqueekCore on Sepolia (887 mm a wheel turn), spins at his real pace, sleeps when he sleeps, and earns him gear at 1, 5, 10, 25, 50 and 100 km. Free, fully on-chain, no owner.",'
        );
        _add(b, '"image":"data:image/svg+xml;base64,');
        _add(b, image);
        _add(b, '","attributes":[');
        _add(
            b,
            abi.encodePacked(
                '{"trait_type":"Distance (km)","display_type":"number","value":', kmText(r.distanceMm), "},"
            )
        );
        _add(b, abi.encodePacked('{"trait_type":"Stage","value":"', stageName(r.stage), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Status","value":"', statusName(r.status), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Display","value":"', displayName(r.display), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Casing","value":"', casingName(r.casing), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Treat","value":"', pouchName(r.pouch), '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Squeek Holder","value":"', r.holder ? "Yes" : "No", '"},'));
        _add(b, abi.encodePacked('{"trait_type":"Water Bottle","value":"', frameName(r.tier), '"},'));
        _add(
            b,
            abi.encodePacked(
                '{"trait_type":"Pace (turns / 30 min)","display_type":"number","value":', r.pace.toString(), "},"
            )
        );
        _add(
            b,
            abi.encodePacked(
                '{"trait_type":"Start Work","display_type":"number","value":', r.startWork.toString(), "},"
            )
        );
        _add(
            b,
            abi.encodePacked(
                '{"trait_type":"Squeek Block Height","display_type":"number","value":',
                uint256(r.blockHeight).toString(),
                "}"
            )
        );
        _add(b, "]}");
        return _done(b);
    }

    /// @notice Kilometres with two decimals, rounded down (12,730,000 mm is "12.73"); whole kilometres from 1,000 km.
    function kmText(uint256 mm) internal pure returns (bytes memory) {
        if (mm >= 1_000_000_000) return bytes((mm / 1_000_000).toString());
        uint256 frac = (mm % 1_000_000) / 10_000;
        return abi.encodePacked((mm / 1_000_000).toString(), ".", frac < 10 ? "0" : "", frac.toString());
    }

    // ---------------------------------------------------------------- traits (rolled at mint from 0..99)

    /// @notice Green LCD 30%, Amber 25%, Red LED 18%, Ice VFD 15%, Nixie 9%, Mechanical 3%.
    function displayOf(uint256 roll) internal pure returns (uint8) {
        uint8[5] memory upTo = [30, 55, 73, 88, 97];
        for (uint8 i; i < 5; i++) {
            if (roll < upTo[i]) return i;
        }
        return 5;
    }

    /// @notice Cream 35%, Silver 30%, Charcoal 25%, Signal Orange 10%: colors that stand out on every stage.
    function casingOf(uint256 roll) internal pure returns (uint8) {
        return roll < 35 ? 0 : roll < 65 ? 1 : roll < 90 ? 2 : 3;
    }

    /// @notice What he holds in his paws: nothing 45%, a sunflower seed 30%, a berry 15%, a coin 8%, a diamond 2%.
    function pouchOf(uint256 roll) internal pure returns (uint8) {
        return roll < 45 ? 0 : roll < 75 ? 1 : roll < 90 ? 2 : roll < 98 ? 3 : 4;
    }

    function displayName(uint8 d) internal pure returns (string memory) {
        string[6] memory n = ["Green LCD", "Amber", "Red LED", "Ice VFD", "Nixie", "Mechanical"];
        return n[d > 5 ? 5 : d];
    }

    function casingName(uint8 c) internal pure returns (string memory) {
        string[4] memory n = ["Cream", "Silver", "Charcoal", "Signal Orange"];
        return n[c > 3 ? 3 : c];
    }

    function pouchName(uint8 p) internal pure returns (string memory) {
        string[5] memory n = ["None", "Sunflower Seed", "Berry", "Coin", "Diamond"];
        return n[p > 4 ? 4 : p];
    }

    function frameName(uint8 t) internal pure returns (string memory) {
        string[5] memory n = ["None", "Bronze", "Silver", "Gold", "Diamond"];
        return n[t > 4 ? 4 : t];
    }

    function stageName(uint8 s) internal pure returns (string memory) {
        string[7] memory n = ["Newbie", "Warm-up", "Jogger", "Runner", "Racer", "Marathoner", "Legend"];
        return n[s > 6 ? 6 : s];
    }

    function statusName(uint8 s) internal pure returns (string memory) {
        string[4] memory n = ["Napping", "Jogging", "Zoomies", "Unknown"];
        return n[s > 3 ? 3 : s];
    }

    // ---------------------------------------------------------------- scene parts

    /// @dev One turn of the art's wheel follows his real pace (work in the last three rounds): 900 ms when he barely
    /// moves, 400 ms at the zoomies line of 1,500, never faster than 240 ms.
    function _spinMs(uint256 pace) private pure returns (uint256) {
        uint256 slow = pace / 3;
        return slow >= 660 ? 240 : 900 - slow;
    }

    function _ms(uint256 ms) private pure returns (string memory) {
        return string.concat(ms.toString(), "ms");
    }

    /// @dev The wheel by stage (steel, bronze from Runner, silver for a Marathoner, gold for a Legend), the bottle's cap
    /// by holder tier (bronze, silver, gold, diamond); the water is always water.
    function _look(Reading memory r) private pure returns (Look memory l) {
        uint8 w = r.stage >= 6 ? 3 : r.stage >= 5 ? 2 : r.stage >= 3 ? 1 : 0;
        l.rimDark = _pick("#5a6274#7a4f2a#7d8696#9a7413", w);
        l.rim = _pick("#9aa3b5#b9773f#c4ccd8#e0b23a", w);
        l.rimLight = _pick("#cfd6e3#e0a46a#f1f4f8#ffe089", w);
        l.cap = _pick("#b9773f#c4ccd8#e0b23a#7fe7ff", r.tier == 0 ? 0 : r.tier > 4 ? 3 : r.tier - 1);
    }

    function _treat(Buf memory b, uint8 p, bool awake, Look memory look) private pure {
        if (p == 1) _layer(b, awake ? Sprites.SEED_RUN : Sprites.SEED_NAP, look);
        if (p == 2) _layer(b, awake ? Sprites.BERRY_RUN : Sprites.BERRY_NAP, look);
        if (p == 3) _layer(b, awake ? Sprites.COIN_RUN : Sprites.COIN_NAP, look);
        if (p >= 4) _layer(b, awake ? Sprites.DIAMOND_RUN : Sprites.DIAMOND_NAP, look);
    }

    /// @dev One piece of gear per stage, the earlier one taken off: a sweat drop (and the wristband on his legs), a
    /// headband with a flapping knot, shoes (on his legs), a race bib with the token's last digit, a medal, then a
    /// cape and a crown. Asleep, only the headband and the crown stay on.
    function _gear(Buf memory b, uint256 id, uint8 stage, bool awake, string memory step, Look memory look)
        private
        pure
    {
        if (stage == 1 && awake) _layer(b, Sprites.SWEAT, look);
        if (stage == 2) {
            if (awake) _frames2(b, Sprites.HEADBAND_0, Sprites.HEADBAND_1, step, look);
            else _layer(b, Sprites.HEADBAND_NAP, look);
        }
        if (stage == 4 && awake) {
            _layer(b, Sprites.BIB, look);
            _add(b, '<path stroke="#d64545" d="');
            _glyph(b, bytes((id % 10).toString())[0], 13, 22, false);
            _add(b, '"/>');
        }
        if (stage == 5 && awake) _layer(b, Sprites.MEDAL, look);
        if (stage == 6) _layer(b, awake ? Sprites.CROWN : Sprites.CROWN_NAP, look);
    }

    /// @dev Confetti for the first 300 m after reaching a new stage.
    function _justLevelled(Reading memory r) private pure returns (bool) {
        if (r.stage == 0 || !r.live) return false;
        uint32[6] memory km = [uint32(1), 5, 10, 25, 50, 100];
        return r.distanceMm - uint256(km[r.stage - 1]) * 1_000_000 < 300_000;
    }

    /// @dev Past 100 km there is no next stage, so every further 100 km lights a pip on the rim (up to 12).
    function _pips(Buf memory b, uint256 mm) private pure {
        uint256 hundreds = mm / 100_000_000;
        if (hundreds < 2) return;
        uint256 n = hundreds - 1 > 12 ? 12 : hundreds - 1;
        bytes memory p = Sprites.PIPS;
        _add(b, '<path stroke="#ffe089" d="');
        for (uint256 k; k < n; k++) {
            _add(b, _run(uint8(p[2 * k]), uint8(p[2 * k + 1]), 1));
        }
        _add(b, '"/>');
    }

    /// @dev The odometer is the wheel's base: a beveled casing and a bezeled screen with the digits flush right, each
    /// display drawn its own way: a dark-on-green LCD, amber, round red LED dots, a VFD over its dot grid, nixie digits
    /// with a glow, or a light mechanical counter whose last digit is red.
    function _odometer(Buf memory b, Reading memory r) private pure {
        uint8 c = r.casing > 3 ? 3 : r.casing;
        uint8 d = r.display > 5 ? 5 : r.display;
        _add(
            b,
            abi.encodePacked(
                '<rect x="6" y="33" width="28" height="7" fill="',
                _pick("#e2d6bc#d9dee6#2a2d33#e8823a", c),
                '"/><rect x="6" y="33" width="28" height="1" fill="',
                _pick("#f4ecd9#f2f4f7#44484f#f5a46a", c),
                '"/><rect x="6" y="39" width="28" height="1" fill="',
                _pick("#b8aa8c#a8afba#17191c#b45f22", c),
                '"/><rect x="8" y="34" width="24" height="5" fill="',
                _pick("#8f8268#7e8592#0d0e10#8a4416", c),
                '"/>'
            )
        );
        _add(
            b,
            abi.encodePacked(
                '<rect x="9" y="34" width="22" height="5" fill="',
                _pick("#9fb58a#1d1405#1a0606#06161a#150a05#ece6d6", d),
                '"/>'
            )
        );
        if (d == 3) _add(b, '<rect x="9" y="34" width="22" height="5" fill="url(#v)"/>');
        // the screen has five digit positions (22 px: "999.99" or "99999"), so like a real odometer it pegs at
        // 99,999 km (the JSON keeps the exact figure); the text is never wider than the screen, so it never leaves it
        bytes memory t = r.live ? kmText(r.distanceMm > MAX_SHOWN_MM ? MAX_SHOWN_MM : r.distanceMm) : bytes("?");
        uint256 w;
        for (uint256 i; i < t.length; i++) {
            w += uint8(Sprites.glyph(t[i])[0]) + 1;
        }
        // flush right on the screen (columns 9..30): the last glyph's spacing pixel falls on column 30
        uint256 x0 = 31 - w;
        if (d == 4) {
            _digits(b, t, x0, '<path stroke="#5a2810" stroke-width="3" stroke-linecap="square" d="', false, false);
        }
        bool counter = d == 5;
        _digits(
            b,
            t,
            x0,
            abi.encodePacked(
                '<path stroke="',
                _pick("#1d2b1d#ffb000#ff4a4a#5ef2ff#ff7a2f#1b1b1b", d),
                d == 2 ? '" stroke-width=".7" stroke-linecap="round" shape-rendering="auto" d="' : '" d="'
            ),
            d == 2,
            counter
        );
    }

    /// @dev One path of digits, as squares or (LED) as round dots; a counter leaves its last digit to a red path.
    function _digits(Buf memory b, bytes memory t, uint256 x, bytes memory open, bool dots, bool counter) private pure {
        _add(b, open);
        uint256 n = counter ? t.length - 1 : t.length;
        for (uint256 i; i < n; i++) {
            x = _glyph(b, t[i], x, 34, dots);
        }
        _add(b, '"/>');
        if (counter) {
            _add(b, '<path stroke="#c0392b" d="');
            _glyph(b, t[t.length - 1], x, 34, false);
            _add(b, '"/>');
        }
    }

    /// @dev Two frames shown one after another every `dur`; the first starts visible, so a still render shows it.
    function _frames2(Buf memory b, bytes memory f0, bytes memory f1, string memory dur, Look memory look)
        private
        pure
    {
        _frame(b, f0, "1", "1;0", dur, look);
        _frame(b, f1, "0", "0;1", dur, look);
    }

    function _frames3(
        Buf memory b,
        bytes memory f0,
        bytes memory f1,
        bytes memory f2,
        string memory dur,
        Look memory look
    ) private pure {
        _frame(b, f0, "1", "1;0;0", dur, look);
        _frame(b, f1, "0", "0;1;0", dur, look);
        _frame(b, f2, "0", "0;0;1", dur, look);
    }

    function _frame(
        Buf memory b,
        bytes memory f,
        string memory start,
        string memory values,
        string memory dur,
        Look memory look
    ) private pure {
        _add(
            b,
            abi.encodePacked(
                '<g opacity="',
                start,
                '"><animate attributeName="opacity" values="',
                values,
                '" dur="',
                dur,
                '" calcMode="discrete" repeatCount="indefinite"/>'
            )
        );
        _layer(b, f, look);
        _add(b, "</g>");
    }

    /// @dev Groups of [color, runs, (x, y, length) * runs] -> one path per group.
    function _layer(Buf memory b, bytes memory data, Look memory look) private pure {
        uint256 i;
        while (i < data.length) {
            uint8 c = uint8(data[i]);
            uint256 runs = uint8(data[i + 1]);
            i += 2;
            _add(b, abi.encodePacked('<path stroke="', _color(c, look), '" d="'));
            for (uint256 k; k < runs; k++) {
                _add(b, _run(uint8(data[i]), uint8(data[i + 1]), uint8(data[i + 2])));
                i += 3;
            }
            _add(b, '"/>');
        }
    }

    /// @dev A glyph at (x, y), as runs or (LED) as one round dot per lit pixel.
    function _glyph(Buf memory b, bytes1 ch, uint256 x, uint256 y, bool dots) private pure returns (uint256) {
        bytes memory g = Sprites.glyph(ch);
        if (g.length == 0) return x;
        uint256 runs = uint8(g[1]);
        for (uint256 k; k < runs; k++) {
            uint256 o = 2 + k * 3;
            uint256 gx = x + uint8(g[o]);
            uint256 gy = y + uint8(g[o + 1]);
            uint256 n = uint8(g[o + 2]);
            if (dots) {
                for (uint256 j; j < n; j++) {
                    _add(b, abi.encodePacked("M", (gx + j).toString(), ".4 ", gy.toString(), ".5h.2"));
                }
            } else {
                _add(b, _run(gx + Sprites.OFF, gy + Sprites.OFF, n));
            }
        }
        return x + uint8(g[0]) + 1;
    }

    /// @dev A run stored with the OFF offset (layers may reach a little past the edge).
    function _run(uint256 x, uint256 y, uint256 n) private pure returns (bytes memory) {
        return abi.encodePacked("M", _coord(x), " ", _coord(y), ".5h", n.toString());
    }

    function _coord(uint256 stored) private pure returns (bytes memory) {
        return stored >= Sprites.OFF
            ? bytes((stored - Sprites.OFF).toString())
            : abi.encodePacked("-", (Sprites.OFF - stored).toString());
    }

    function _color(uint8 c, Look memory look) private pure returns (bytes memory) {
        if (c == RIM_DARK) return look.rimDark;
        if (c == RIM) return look.rim;
        if (c == RIM_LIGHT) return look.rimLight;
        if (c == CAP) return look.cap;
        return _slice(Sprites.PALETTE, uint256(c) * 7, 7);
    }

    /// @dev The i-th 7-character color of a list.
    function _pick(bytes memory list, uint256 i) private pure returns (bytes memory) {
        return _slice(list, i * 7, 7);
    }

    function _slice(bytes memory s, uint256 from, uint256 len) private pure returns (bytes memory out) {
        out = new bytes(len);
        for (uint256 i; i < len; i++) {
            out[i] = s[from + i];
        }
    }

    // ---------------------------------------------------------------- a write-once buffer

    struct Buf {
        bytes data;
        uint256 len;
    }

    function _buf(uint256 cap) private pure returns (Buf memory b) {
        b.data = new bytes(cap);
    }

    function _add(Buf memory b, bytes memory s) private pure {
        uint256 n = b.len;
        uint256 l = s.length;
        bytes memory d = b.data;
        require(n + l <= d.length, "OdometerArt: buffer");
        assembly ("memory-safe") {
            mcopy(add(add(d, 0x20), n), add(s, 0x20), l)
        }
        b.len = n + l;
    }

    function _done(Buf memory b) private pure returns (bytes memory d) {
        d = b.data;
        uint256 n = b.len;
        assembly ("memory-safe") {
            mstore(d, n)
        }
    }
}
