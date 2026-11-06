#!/usr/bin/env python3
"""Render the original gallery locally without FFI, EVM filesystem grants, RPCs or broadcasting.

    python3 tools/export_gallery.py          # write previews/gallery.html and the ten site SVGs
    python3 tools/export_gallery.py --check  # compare the ten committed SVGs without changing them

Requires only Python's standard library and the pinned Foundry project. Forge returns ABI-encoded
strings; this utility decodes just (string, string[]) and writes a fixed set of local paths.
"""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ["placeholder.svg", "favicon.svg"] + [f"samples/stage-{i}.svg" for i in range(7)] + ["samples/napping.svg"]


def decode_outputs(encoded):
    data = bytes.fromhex(encoded.removeprefix("0x"))

    def word(offset):
        if offset < 0 or offset + 32 > len(data):
            raise ValueError("Truncated gallery ABI word")
        return int.from_bytes(data[offset:offset + 32], "big")

    def string_at(offset):
        length = word(offset)
        end = offset + 32 + length
        if end > len(data):
            raise ValueError("Truncated gallery ABI string")
        return data[offset + 32:end].decode("utf-8")

    gallery = string_at(word(0))
    array = word(32)
    count = word(array)
    if count != len(ASSETS):
        raise ValueError(f"Expected {len(ASSETS)} assets, got {count}")
    base = array + 32
    assets = [string_at(base + word(base + 32 * i)) for i in range(count)]
    return gallery, assets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare committed SVGs instead of writing files")
    args = parser.parse_args()
    result = subprocess.run(
        ["forge", "script", "script/Gallery.s.sol:Gallery", "--json"],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )
    if result.returncode:
        raise SystemExit(result.stderr or result.stdout)
    report = json.loads(result.stdout)
    if not report.get("success"):
        raise SystemExit("Gallery rendering failed")
    gallery, assets = decode_outputs(report["returned"])
    for name, svg in zip(ASSETS, assets):
        path = ROOT / "dist" / name
        if args.check:
            if not path.exists() or path.read_bytes() != svg.encode("utf-8"):
                raise SystemExit(f"SVG missing or stale: dist/{name}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(svg.encode("utf-8"))
    if not args.check:
        destination = ROOT / "previews" / "gallery.html"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(gallery, encoding="utf-8")
    print(f"{'Checked' if args.check else 'Exported'} {len(assets)} original SVG assets; gallery rendered locally")


if __name__ == "__main__":
    main()
