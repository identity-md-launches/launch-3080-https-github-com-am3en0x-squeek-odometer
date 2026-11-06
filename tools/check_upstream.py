#!/usr/bin/env python3
"""Check the imported source, art, dependencies and site offline against their pinned upstream hashes."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    provenance = json.loads((ROOT / "docs" / "UPSTREAM.json").read_text())
    failures = []
    for name, expected in provenance["files"].items():
        path = ROOT / name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            failures.append(name)
    if failures:
        raise SystemExit("Imported files differ from pinned upstream:\n" + "\n".join(failures))
    print(f'Checked {len(provenance["files"])} unchanged files at {provenance["commit"]}')


if __name__ == "__main__":
    main()
