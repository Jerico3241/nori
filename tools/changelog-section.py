#!/usr/bin/env python3
"""Schneidet den Abschnitt einer Version aus CHANGELOG.md heraus.

Wird vom Release-Workflow gebraucht: die Release-Notiz soll dasselbe sagen wie
der Changelog, ohne dass jemand sie ein zweites Mal tippt.

    python3 tools/changelog-section.py macOS 1.10.2

Überschriften sehen so aus:

    ## [macOS 1.10.2] · [iOS 1.9.4] – 2026-09-05
    ## [iOS 1.9.2] – 2026-09-05

Gesucht wird also nach `[<Plattform> <Version>]` irgendwo in der Überschrift;
gemeinsame Einträge zweier Plattformen werden damit von beiden gefunden.
Exit-Code 1, wenn es den Abschnitt nicht gibt — dann fehlt der Changelog-Eintrag
zur Version, und der Release soll nicht stillschweigend leer bleiben.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def section(platform: str, version: str) -> str | None:
    changelog = ROOT / "CHANGELOG.md"
    if not changelog.exists():
        return None

    wanted = f"[{platform} {version}]"
    lines = changelog.read_text().splitlines()
    out: list[str] = []
    inside = False

    for line in lines:
        if line.startswith("## "):
            if inside:
                break
            inside = wanted in line
            continue
        if inside:
            out.append(line)

    text = "\n".join(out).strip()
    return text or None


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    platform, version = sys.argv[1], sys.argv[2]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        print(f"Version sieht nicht nach x.y.z aus: {version}", file=sys.stderr)
        return 2

    text = section(platform, version)
    if text is None:
        print(
            f"Kein Changelog-Abschnitt für [{platform} {version}]. "
            "Vor dem Tag gehört ein Eintrag in CHANGELOG.md.",
            file=sys.stderr,
        )
        return 1

    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
