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


def pick(triples: set[str], prefix: str, api: int) -> str:
    """Das Tripel zur gewünschten API-Ebene.

    Entscheidend ist, dass sie zu `minSdk` der App passt und **nicht** die
    höchste verfügbare ist. Gegen API 36 gebaut, setzt der Compiler
    `__ANDROID_API__=36` und darf Symbole verwenden, die es auf einem Gerät
    mit Android 9 nicht gibt. Die APK ließe sich dort installieren und stürbe
    beim Laden der Bibliothek — ein Fehler, den kein Build zeigt und den ein
    Emulator mit aktuellem Android nie auslöst.
    """
    exact = f"{prefix}{api}"
    if exact in triples:
        return exact
    # Sonst das nächstniedrigere: lieber älter als zu neu.
    lower = sorted(
        (t for t in triples if t.startswith(prefix) and level_of(t, prefix) <= api),
        key=lambda t: level_of(t, prefix),
    )
    return lower[-1] if lower else ""


def level_of(triple: str, prefix: str) -> int:
    tail = triple[len(prefix):]
    return int(tail) if tail.isdigit() else -1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github-output", action="store_true")
    parser.add_argument(
        "--api",
        type=int,
        default=28,
        help="API-Ebene, gegen die gebaut wird. Muss zu minSdk der App passen.",
    )
    args = parser.parse_args()

    triples, seen = discover()
    android = {t for t in triples if "android" in t}

    lines = [
        "all=" + " ".join(sorted(android)),
        "arm64=" + pick(android, "aarch64-unknown-linux-android", args.api),
        "x86_64=" + pick(android, "x86_64-unknown-linux-android", args.api),
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
