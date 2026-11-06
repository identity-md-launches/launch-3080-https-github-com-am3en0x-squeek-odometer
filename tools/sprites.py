"""Pixel sprites for the Squeek Odometer: Squeektoshi by hand, a hand-drawn wheel, the odometer as its base.

Builds every layer of the scene and writes them to src/art/Sprites.sol as compact run data: groups of
[color index, run count, (x, y, length) * count], one byte each. The contract turns a group into one SVG
<path stroke="color" d="M x y.5 h length ..."/>. Coordinates are stored with an offset of OFF (the contract
subtracts it), so a layer may run past the edge. The scene is drawn on a 40x40 grid and shown through a 32x32 window
(x 4..35, y 8..39), so the wheel's top crops off and Squeektoshi fills the frame.

To look at the result, render the contract's own SVG: python3 tools/export_gallery.py

    python tools/sprites.py            # writes src/art/Sprites.sol
"""
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = H = 40
OFF = 8  # stored coordinate = real + OFF, so -8..247 fits a byte

# ---------------------------------------------------------------- palette
# Slots marked (stage) or (tier) are recolored by the contract; the color here is a default.
PALETTE = [None] + [
    "#2a1a10",  # 1 outline
    "#9a6b3f",  # 2 dark fur
    "#c99762",  # 3 fur (Squeektoshi's tan)
    "#e2c08f",  # 4 light fur
    "#f4e6cc",  # 5 cream
    "#f2a0a8",  # 6 pink
    "#1a1110",  # 7 eye
    "#ffffff",  # 8 white
    "#d9737e",  # 9 nose
    "#5a6274",  # 10 rim dark (stage)
    "#9aa3b5",  # 11 rim (stage)
    "#cfd6e3",  # 12 rim light (stage)
    "#9a7413",  # 13 gold dark
    "#e0b23a",  # 14 gold
    "#ffe089",  # 15 gold light
    "#d64545",  # 16 red
    "#9e2f2f",  # 17 red dark
    "#4a74c9",  # 18 blue
    "#7d55c7",  # 19 cape
    "#5a3a96",  # 20 cape dark
    "#9fd8ff",  # 21 sweat
    "#b9925a",  # 22 bedding
    "#8c6a3c",  # 23 bedding dark
    "#e8dcc8",  # 24 dust
    "#f1f0ff",  # 25 star
    "#cfe8f5",  # 26 bottle glass
    "#a9dcf5",  # 27 bottle water
    "#9a7413",  # 28 bottle cap and clip (tier)
    "#e9dcb0",  # 29 seed light
    "#7fc4a4",  # 30 mint (confetti)
    "#fff3c4",  # 31 white gold (crown)
    "#b8c0cc",  # 32 spout metal
    "#3fa34d",  # 33 leaf
    "#2a2620",  # 34 seed dark
    "#d6334a",  # 35 berry
    "#7fe7ff",  # 36 diamond
]
NAMES = ["_", "outline", "dfur", "fur", "lfur", "cream", "pink", "eye", "white", "nose", "rimd", "rim", "riml",
         "goldd", "gold", "goldl", "red", "redd", "blue", "cape", "caped", "sweat", "bed", "bedd", "dust", "star",
         "glass", "water", "cap", "seed", "mint", "wgold", "metal", "leaf", "seedd", "berry", "diam"]
C = {n: i for i, n in enumerate(NAMES)}
assert len(PALETTE) == len(NAMES)


# ---------------------------------------------------------------- helpers
def rows_px(x0, y0, rows, legend):
    out = {}
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch != ".":
                out[(x0 + i, y0 + j)] = C[legend[ch]]
    return out


def paint(points, color):
    return {p: C[color] for p in points}


def merge(*layers):
    out = {}
    for l in layers:
        out.update(l)
    return out


def circle(cx, cy, r):
    """Clean 1-px circle (midpoint algorithm)."""
    pts, x, y, err = set(), r, 0, 1 - r
    while x >= y:
        for a, b in ((x, y), (y, x), (-y, x), (-x, y), (-x, -y), (-y, -x), (y, -x), (x, -y)):
            pts.add((cx + a, cy + b))
        y += 1
        if err < 0:
            err += 2 * y + 1
        else:
            x -= 1
            err += 2 * (y - x) + 1
    return pts


# ---------------------------------------------------------------- Squeektoshi
# Side view, facing right. o outline, d dark fur, f fur, l light fur, c cream, p pink, e eye, w eye light, n nose.
COAT = {"o": "outline", "d": "dfur", "f": "fur", "l": "lfur", "c": "cream", "p": "pink", "e": "eye", "w": "white",
        "n": "nose"}
SQUEEK_RUN = [
    "..........oo..oo......",
    "......oooodpooppo.....",
    "....oodffffoodpplo....",
    "...odffffffffffllloo..",
    "..odfffffffffffleewlo.",
    ".odffffffffffffleeelno",
    ".odfffffffffflllccccpo",
    "oddfffffffflllccccccoo",
    "oddfffffllllccccccccco",
    ".odffllllllcccccccccco",
    "..oddcccccccccccccoo..",
    "...oooooooooooooooo...",
]
EARS_BACK = [  # zoomies: ears pinned back
    "......................",
    "......oooooodppoo.....",
]
LEGS = [  # two frames under the body: stretched, then gathered
    ["..odo..........opo....", ".odo............opo..."],
    ["....odo.....opo.......", ".....oo......po........"],
]
SQUEEK_NAP = [  # curled up asleep, eyes shut, one ear up
    ".....oooooo.oo..",
    "...oodfffffoppo.",
    "..odffffffflloo.",
    ".odfffffffflllo.",
    ".odffffffflleeo.",
    "oddfffffflllllpo",
    "oddffffflllcccco",
    ".oddffllcccccco.",
    "..ooddcccccooo..",
    "....oooooooo....",
]
RUN_AT = (9, 19)
NAP_AT = (12, 23)
WCX, WCY, R = 20, 17, 17


def at(origin, pts):
    ox, oy = origin
    return {(ox + x, oy + y) for (x, y) in pts}


# ---------------------------------------------------------------- the wheel
def rim():
    return merge(paint(circle(WCX, WCY, R), "rimd"), paint(circle(WCX, WCY, R - 1), "rim"))


def wheel_frame(f):
    """Spokes and tread rungs in three frames that turn one way: the spokes step 30 degrees (their pattern repeats
    every 90), the rungs 10 (they repeat every 30), and frame 0 is off-axis, so a still never shows a crosshair."""
    sp = set()
    for k in range(4):
        a = math.radians(22 + f * 30 + k * 90)
        for t in range(2, R - 2):
            sp.add((round(WCX + t * math.cos(a)), round(WCY + t * math.sin(a))))
    rg = set()
    for k in range(12):
        a = math.radians(k * 30 + f * 10)
        for r in (R - 2, R - 3):
            rg.add((round(WCX + r * math.cos(a)), round(WCY + r * math.sin(a))))
    return merge(paint(sp, "rimd"), paint(rg, "riml"))


def hub():
    return paint({(WCX, WCY), (WCX + 1, WCY), (WCX, WCY + 1), (WCX + 1, WCY + 1)}, "riml")


def pips():
    """Where the endless-ladder pips go: 12 points on the visible part of the rim, left to right over the top."""
    out = []
    for k in range(12):
        a = math.radians(-160 + k * (140 / 11))
        out.append((round(WCX + R * math.cos(a)), round(WCY + R * math.sin(a))))
    return out


# ---------------------------------------------------------------- gear, one shape per stage
def gear():
    g = {}
    g["SWEAT"] = paint(at(RUN_AT, {(9, -2), (9, -1), (11, -3), (12, -4), (7, -1)}), "sweat")  # Warm-up, with a wristband
    band = at(RUN_AT, {(x, 3) for x in range(12, 18)})
    g["HEADBAND_0"] = merge(paint(band, "red"), paint(at(RUN_AT, {(11, 3), (10, 2), (9, 2)}), "redd"))  # Jogger
    g["HEADBAND_1"] = merge(paint(band, "red"), paint(at(RUN_AT, {(11, 3), (10, 4), (9, 4)}), "redd"))
    # Racer: a race bib; the contract writes the token's last digit on it
    g["BIB"] = merge(paint(at(RUN_AT, {(x, y) for x in range(3, 8) for y in range(2, 9)}), "white"),
                     paint(at(RUN_AT, {(3, 2), (7, 2)}), "redd"))
    g["MEDAL"] = merge(paint(at(RUN_AT, {(12, 7), (13, 8)}), "red"),
                       paint(at(RUN_AT, {(13, 9), (14, 9), (13, 10), (14, 10)}), "gold"),
                       paint(at(RUN_AT, {(13, 9)}), "goldl"))  # Marathoner
    crown = at(RUN_AT, {(x, 0) for x in range(12, 18)} | {(12, -1), (14, -1), (16, -1)})
    g["CROWN"] = merge(paint(crown, "wgold"), paint(at(RUN_AT, {(15, 0)}), "red"))

    def cape(f):
        # hangs from a gold clasp at the neck, over the shoulders and back, with a scalloped hem that flutters
        body = {(x, y) for x in range(-5 + f, 12) for y in range(1, 9)
                if y >= 1 + (11 - x) * 0.22 and y <= 2.5 + (x + 6 - f) * 0.55}
        hem = {(x, 8 if (x + f) % 2 else 7) for x in range(-4 + f, 6)}
        return merge(paint(at(RUN_AT, body | hem), "cape"),
                     paint(at(RUN_AT, {(x, 7) for x in range(-4 + f, 6) if (x + f) % 2}), "caped"),
                     paint(at(RUN_AT, {(12, 5)}), "gold"))
    g["CAPE_0"] = cape(0)
    g["CAPE_1"] = cape(1)
    # asleep, the headband and the crown stay on, on the ball's head
    g["HEADBAND_NAP"] = paint(at(NAP_AT, {(x, 2) for x in range(8, 12)} | {(7, 2)}), "red")
    g["CROWN_NAP"] = merge(paint(at(NAP_AT, {(x, -1) for x in range(5, 10)} | {(5, -2), (7, -2), (9, -2)}), "wgold"),
                           paint(at(NAP_AT, {(7, -1)}), "red"))
    return g


def feet(frame):
    row = LEGS[frame][1]
    return [i for i, ch in enumerate(row) if ch != "."]


def shoes(frame):
    """Runner's shoes: the feet in blue with a white toe."""
    out = {}
    fs = feet(frame)
    y = RUN_AT[1] + len(SQUEEK_RUN) + 1
    for i in fs:
        out[(RUN_AT[0] + i, y)] = C["blue"]
    groups, cur = [], []
    for i in fs:
        if cur and i != cur[-1] + 1:
            groups.append(cur)
            cur = []
        cur.append(i)
    if cur:
        groups.append(cur)
    for gpx in groups:
        out[(RUN_AT[0] + gpx[-1], y)] = C["white"]
    return out


def wristband(frame):
    """Warm-up: a sweatband on the front leg, frame by frame."""
    row = LEGS[frame][0]
    front = [i for i, ch in enumerate(row) if ch != "."][-3:]
    return paint({(RUN_AT[0] + i, RUN_AT[1] + len(SQUEEK_RUN)) for i in front}, "sweat")


def treat(kind, pose):
    """A treat held at his mouth, outlined, with a highlight: a striped seed, a berry with a leaf, a coin with a rim,
    a diamond with a facet."""
    ox, oy = (RUN_AT[0] + 21, RUN_AT[1] + 6) if pose == "run" else (NAP_AT[0] + 15, NAP_AT[1] + 4)
    p = lambda pts: {(ox + x, oy + y) for (x, y) in pts}
    if kind == "SEED":
        return merge(paint(p({(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2)}), "seed"),
                     paint(p({(1, 0), (0, 1), (1, 2)}), "seedd"))
    if kind == "BERRY":
        return merge(paint(p({(0, 1), (1, 1), (0, 2), (1, 2)}), "berry"), paint(p({(1, 0)}), "leaf"),
                     paint(p({(0, 1)}), "white"))
    if kind == "COIN":
        return merge(paint(p({(0, 0), (1, 0), (2, 0), (0, 1), (2, 1), (0, 2), (1, 2), (2, 2)}), "goldd"),
                     paint(p({(1, 1)}), "goldl"))
    return merge(paint(p({(0, 1), (1, 0), (1, 1), (2, 1), (1, 2)}), "diam"), paint(p({(1, 0)}), "white"))


def dust(frame):
    """Dust kicked up at his heels, inside the rim."""
    pts = {(10, 30), (9, 31), (10, 31), (8, 30)} if frame == 0 else {(9, 29), (8, 30), (9, 30), (7, 29)}
    return paint(pts, "dust")


def bedding():
    return merge(paint({(x, 32) for x in range(9, 32)}, "bed"),
                 paint({(x, 31) for x in range(10, 31) if x % 3}, "bed"),
                 paint({(x, 32) for x in range(9, 32) if x % 4 == 1}, "bedd"))


def zzz():
    return merge(rows_px(28, 18, ["zz.", ".z.", ".zz"], {"z": "star"}),
                 rows_px(31, 14, ["zz.", ".z.", ".zz"], {"z": "star"}))


def moon():
    pts = {(x, y) for x in range(29, 34) for y in range(9, 14) if (x - 31) ** 2 + (y - 11) ** 2 <= 5}
    bite = {(x, y) for x in range(29, 35) for y in range(8, 14) if (x - 32.4) ** 2 + (y - 10.2) ** 2 <= 4}
    return paint(pts - bite, "goldl")


def stars():
    return paint({(6, 10), (25, 9), (34, 17), (5, 22), (35, 27), (13, 11)}, "star")


def bottle():
    """The holder's water bottle, clipped to the cage by a wire: rounded glass, water, the cap and clip in the tier's
    metal, a spout."""
    glass = {(x, y) for x in range(5, 9) for y in range(11, 21)}
    edge = {(x, y) for (x, y) in glass if x in (5, 8) or y == 11} | {(6, 21), (7, 21)}
    water = {(x, y) for x in range(6, 8) for y in range(14, 21)}
    return merge(paint(glass, "glass"), paint(edge, "outline"), paint(water, "water"),
                 paint({(x, y) for x in range(5, 9) for y in (9, 10)} | {(9, 9), (10, 9)}, "cap"),
                 paint({(7, 22), (8, 23)}, "metal"), paint({(6, 12)}, "white"))


def confetti():
    """2-pixel pieces; the contract lets them fall."""
    return merge(paint({(12, 10), (12, 11), (27, 12), (28, 12)}, "red"),
                 paint({(18, 9), (19, 9), (9, 15), (9, 16)}, "gold"),
                 paint({(23, 14), (23, 15), (31, 18), (32, 18)}, "blue"),
                 paint({(15, 14), (16, 14), (26, 9), (26, 10)}, "mint"))


# 3x5 font: digits, dot, question mark
FONT = {
    "0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
    "2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
    "4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
    "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
    "8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
    ".": [".", ".", ".", ".", "#"], "?": ["###", "..#", ".##", "...", ".#."],
}

LAYERS = {}


def build():
    LAYERS["RIM"] = rim()
    for f in (0, 1, 2):
        LAYERS[f"WHEEL_{f}"] = wheel_frame(f)
    LAYERS["HUB"] = hub()
    LAYERS["SQUEEK_RUN"] = rows_px(*RUN_AT, SQUEEK_RUN, COAT)
    LAYERS["SQUEEK_ZOOM"] = rows_px(*RUN_AT, EARS_BACK + SQUEEK_RUN[2:], COAT)
    for f in (0, 1):
        LAYERS[f"LEGS_{f}"] = rows_px(RUN_AT[0], RUN_AT[1] + len(SQUEEK_RUN), LEGS[f], COAT)
        LAYERS[f"SHOES_{f}"] = shoes(f)
        LAYERS[f"WRIST_{f}"] = wristband(f)
        LAYERS[f"DUST_{f}"] = dust(f)
    LAYERS["SQUEEK_NAP"] = rows_px(*NAP_AT, SQUEEK_NAP, COAT)
    LAYERS["BEDDING"] = bedding()
    LAYERS.update(gear())
    for kind in ("SEED", "BERRY", "COIN", "DIAMOND"):
        LAYERS[f"{kind}_RUN"] = treat(kind, "run")
        LAYERS[f"{kind}_NAP"] = treat(kind, "nap")
    LAYERS["ZZZ"] = zzz()
    LAYERS["MOON"] = moon()
    LAYERS["STARS"] = stars()
    LAYERS["BOTTLE"] = bottle()
    LAYERS["CONFETTI"] = confetti()


# ---------------------------------------------------------------- encoding
def runs(px):
    by_color = {}
    ys = sorted({y for (_, y) in px})
    for y in ys:
        xs = sorted(x for (x, yy) in px if yy == y)
        i = 0
        while i < len(xs):
            c = px[(xs[i], y)]
            start = xs[i]
            j = i
            while j + 1 < len(xs) and xs[j + 1] == xs[j] + 1 and px[(xs[j + 1], y)] == c:
                j += 1
            by_color.setdefault(c, []).append((start, y, xs[j] - start + 1))
            i = j + 1
    return by_color


def encode(px):
    out = bytearray()
    for c, rs in sorted(runs(px).items()):
        for i in range(0, len(rs), 255):
            part = rs[i:i + 255]
            out += bytes([c, len(part)])
            for (x, y, n) in part:
                assert -OFF <= x and x + OFF < 256 and -OFF <= y and y + OFF < 256
                out += bytes([x + OFF, y + OFF, n])
    return bytes(out)


def glyph_runs(ch):
    rows = FONT[ch]
    out = []
    for dy, row in enumerate(rows):
        dx = 0
        while dx < len(row):
            if row[dx] != "#":
                dx += 1
                continue
            s = dx
            while dx < len(row) and row[dx] == "#":
                dx += 1
            out.append((s, dy, dx - s))
    return len(rows[0]), out


def write_solidity():
    lines = [
        "// SPDX-License-Identifier: MIT",
        "// GENERATED by tools/sprites.py. Do not edit by hand: change the generator and run it again.",
        "pragma solidity 0.8.26;",
        "",
        "/// @notice Pixel layers of the scene: groups of [color, runs, (x, y, length) * runs], one byte each, with x and y",
        f"/// stored + OFF ({OFF}) so a layer may run past the edge.",
        "library Sprites {",
        f"    uint256 internal constant OFF = {OFF};",
        "    /// @notice 7-character hex colors, index 0 unused. Some slots are recolored per token by OdometerArt.",
        '    bytes internal constant PALETTE = "' + "".join(c or "#000000" for c in PALETTE) + '";',
    ]
    for name, px in LAYERS.items():
        lines.append(f"    bytes internal constant {name} = hex\"{encode(px).hex()}\";")
    pip_bytes = b"".join(bytes([x + OFF, y + OFF]) for (x, y) in pips())
    lines.append("    /// @notice The 12 rim points for the endless-ladder pips, over the top from left to right: (x, y) + OFF.")
    lines.append(f"    bytes internal constant PIPS = hex\"{pip_bytes.hex()}\";")
    lines.append("")
    lines.append("    /// @notice A glyph of the odometer font: [width, runs, (dx, dy, length) * runs].")
    lines.append("    function glyph(bytes1 ch) internal pure returns (bytes memory) {")
    for ch in FONT:
        w, rs = glyph_runs(ch)
        data = bytes([w, len(rs)]) + b"".join(bytes(r) for r in rs)
        lines.append(f"        if (ch == \"{ch}\") return hex\"{data.hex()}\";")
    lines.append("        return hex\"\";")
    lines.append("    }")
    lines.append("}")
    path = os.path.join(ROOT, "src", "art", "Sprites.sol")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    total = sum(len(encode(px)) for px in LAYERS.values())
    print(f"wrote {path}: {len(LAYERS)} layers, {total} bytes of run data; recolored slots: " +
          ", ".join(f"{n}={i}" for n, i in C.items() if n in ("rimd", "rim", "riml", "cap")))


if __name__ == "__main__":
    build()
    write_solidity()
