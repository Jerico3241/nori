#!/usr/bin/env python3
"""Findet die Ziel-Tripel des installierten Swift-SDK für Android.

Warum ein eigenes Skript: `swift sdk list` nennt nur den Bündelnamen, und die
Tripel im `info.json` des Bündels sind die **Host**-Tripel — der Rechner, auf
dem gebaut wird, nicht das Ziel. Die Zieltripel stehen eine Ebene tiefer in
`swift-sdk.json`, und der Schlüssel dafür heißt je nach Schemafassung
`targetTriples` oder `runTimeTriples`.

Ein falsches Tripel sieht im Build aus wie ein fehlendes SDK. Deshalb wird
hier gesucht und bei Misserfolg der tatsächliche Verzeichnisbaum ausgegeben,
statt mit einer Vermutung weiterzumachen.

    python3 tools/android-triples.py --github-output
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOTS = [Path.home() / ".swiftpm" / "swift-sdks"]

# Schlüssel, unter denen die Zieltripel je nach Schemafassung stehen.
TRIPLE_KEYS = ("targetTriples", "runTimeTriples")


def discover() -> tuple[set[str], list[Path]]:
    triples: set[str] = set()
    seen: list[Path] = []
    for root in ROOTS:
        if not root.is_dir():
            continue
        for name in ("swift-sdk.json", "destination.json"):
            for path in root.rglob(name):
                seen.append(path)
                try:
                    data = json.loads(path.read_text())
                except (OSError, json.JSONDecodeError):
                    continue
                for key in TRIPLE_KEYS:
                    value = data.get(key)
                    if isinstance(value, dict):
                        triples.update(value.keys())
                # Ältere destination.json nennen genau ein Tripel.
                single = data.get("target")
                if isinstance(single, str):
                    triples.add(single)
    return triples, seen


def pick(triples: set[str], prefix: str) -> str:
    # Bei mehreren API-Ständen (…android24, …android28) das höchste nehmen:
    # es entspricht dem, was `minSdk` in der App verlangt.
    hits = sorted(t for t in triples if t.startswith(prefix))
    return hits[-1] if hits else ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github-output", action="store_true")
    args = parser.parse_args()

    triples, seen = discover()
    android = {t for t in triples if "android" in t}

    lines = [
        "all=" + " ".join(sorted(android)),
        "arm64=" + pick(android, "aarch64-unknown-linux-android"),
        "x86_64=" + pick(android, "x86_64-unknown-linux-android"),
    ]

    if args.github_output:
        print("\n".join(lines))

    print("Gefundene SDK-Beschreibungen:", file=sys.stderr)
    for path in seen:
        print(f"  {path}", file=sys.stderr)
    print(f"Alle Tripel: {sorted(triples)}", file=sys.stderr)

    if not android:
        print("\nKein Android-Tripel gefunden. Vorhanden ist:", file=sys.stderr)
        for root in ROOTS:
            if not root.is_dir():
                print(f"  {root} existiert nicht", file=sys.stderr)
                continue
            for path in sorted(root.rglob("*.json"))[:60]:
                print(f"  {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
