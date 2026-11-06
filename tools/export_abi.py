#!/usr/bin/env python3
"""Export or check the SqueekOdometer ABI from the local, already-built Foundry artifact. No network or wallet access.

    forge build && python3 tools/export_abi.py           # writes docs/abi/SqueekOdometer.json
    forge build && python3 tools/export_abi.py --check   # fails if it is missing or stale
"""
import argparse
import json
from pathlib import Path

CONTRACTS = ("SqueekOdometer",)
ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if an exported ABI is absent or stale")
    args = parser.parse_args()
    for name in CONTRACTS:
        artifact = ROOT / "out" / f"{name}.sol" / f"{name}.json"
        abi = json.loads(artifact.read_text(encoding="utf-8"))["abi"]
        dest = ROOT / "docs" / "abi" / f"{name}.json"
        if args.check:
            if not dest.exists() or json.loads(dest.read_text(encoding="utf-8")) != abi:
                raise SystemExit(f"ABI missing or stale: {dest.relative_to(ROOT)}")
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(json.dumps(abi, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(f"{'Checked' if args.check else 'Exported'} {name}")


if __name__ == "__main__":
    main()
