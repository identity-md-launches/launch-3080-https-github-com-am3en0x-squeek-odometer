// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OdometerArt} from "../src/art/OdometerArt.sol";
import {Reading} from "../src/Types.sol";

/// @notice Returns the gallery and site assets without filesystem permissions, network access or broadcasting.
/// @dev `python3 tools/export_gallery.py` writes the returned data outside the EVM.
contract Gallery {
    function run() external pure returns (string memory gallery, string[] memory assets) {
        assets = new string[](10);
        uint256[7] memory mm = [uint256(420_000), 1_070_000, 5_310_000, 12_730_000, 27_900_000, 58_120_000, 104_660_000];
        string[7] memory stages = ["Newbie", "Warm-up", "Jogger", "Runner", "Racer", "Marathoner", "Legend"];
        string[4] memory statuses = ["Jogging", "Zoomies", "Napping", "Unknown (SqueekCore unreadable)"];
        string memory html = string.concat(
            '<!doctype html><meta charset="utf-8"><title>Squeek Odometer gallery</title>',
            '<body style="background:#0d1017;color:#e6e9ef;font:14px system-ui;margin:24px">',
            "<h1 style=\"font:600 22px ui-monospace,monospace\">Squeek Odometer: every stage and status</h1>",
            '<p style="color:#9aa3b5">Rendered by the contract itself. The water bottle is the holder reward (bronze, silver, gold, diamond).</p>'
        );
        for (uint8 stage; stage < 7; stage++) {
            html = string.concat(
                html,
                '<h2 style="font:600 15px ui-monospace,monospace;color:#9aa3b5;margin:22px 0 8px">',
                stages[stage],
                "</h2><div>"
            );
            for (uint8 k; k < 4; k++) {
                Reading memory r;
                r.stage = stage;
                r.status = k == 3 ? 3 : (k == 0 ? 1 : (k == 1 ? 2 : 0));
                r.distanceMm = mm[stage];
                r.live = r.status != 3;
                r.display = (stage + k) % 6;
                r.casing = (stage * 2 + k) % 4;
                r.pouch = (stage + k) % 5;
                r.tier = (stage + k) % 5;
                r.holder = r.tier > 0;
                r.pace = r.status == 2 ? 1_800 : r.status == 1 ? 600 : 0;
                html = string.concat(
                    html,
                    '<figure style="display:inline-block;margin:0 14px 10px 0;text-align:center">',
                    string(OdometerArt.svg(uint256(stage) * 4 + k + 1, r)),
                    '<figcaption style="color:#9aa3b5;font:12px ui-monospace,monospace">',
                    statuses[k],
                    " &middot; ",
                    OdometerArt.displayName(r.display),
                    " &middot; ",
                    OdometerArt.casingName(r.casing),
                    " &middot; ",
                    OdometerArt.pouchName(r.pouch),
                    " &middot; bottle ",
                    OdometerArt.frameName(r.tier),
                    "</figcaption></figure>"
                );
            }
            html = string.concat(html, "</div>");
        }
        gallery = string.concat(html, "</body>");
        // the site's placeholder and icon: a fresh odometer, jogging at 0.00 km
        Reading memory fresh;
        fresh.status = 1;
        fresh.live = true;
        assets[0] = string(OdometerArt.svg(1, fresh));
        assets[1] = assets[0];
        // the site's stage strip: one odometer per stage, each with another display, casing, treat and bottle
        uint8[7] memory displays = [0, 1, 2, 3, 4, 5, 1];
        uint8[7] memory pouches = [0, 1, 2, 3, 4, 1, 4];
        uint8[7] memory tiers = [0, 0, 1, 2, 3, 4, 3];
        for (uint8 stage; stage < 7; stage++) {
            Reading memory r;
            r.stage = stage;
            r.status = stage % 3 == 1 ? 2 : 1;
            r.live = true;
            r.distanceMm = mm[stage];
            r.display = displays[stage];
            r.casing = stage % 4;
            r.pouch = pouches[stage];
            r.tier = tiers[stage];
            r.holder = r.tier > 0;
            r.pace = r.status == 2 ? 1_800 : 600;
            assets[uint256(stage) + 2] = string(OdometerArt.svg(uint256(stage) + 3, r));
        }
        Reading memory nap;
        nap.stage = 2;
        nap.live = true;
        nap.distanceMm = 6_240_000;
        nap.display = 3;
        nap.casing = 2;
        nap.pouch = 1;
        assets[9] = string(OdometerArt.svg(12, nap));
    }
}
