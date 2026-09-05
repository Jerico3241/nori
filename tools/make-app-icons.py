#!/usr/bin/env python3
"""Erzeugt beide App-Icon-Sets aus einem einzigen Master.

Master ist `native/Nori-macOS/Nori/Assets.xcassets/AppIcon.appiconset/icon.png`
in 1024×1024. Daraus entstehen:

- macOS: alle von `Contents.json` verlangten Größen, RGBA (Alphakanal erlaubt
  und erwünscht — macOS-Icons sind abgerundet und dürfen transparente Ecken
  haben).
- iOS: ein einzelnes 1024×1024-Icon **ohne** Alphakanal. Der App-Store und der
  Asset-Catalog verlangen ein deckendes Bild; ein transparentes wird beim Bauen
  stillschweigend verworfen und der Build meldet dann nur noch
  „app icon set named 'AppIcon' did not have any applicable content".

Der Untergrund für iOS wird aus den Randpixeln des Masters gemittelt, damit
das Icon nicht auf Weiß, sondern auf der eigenen Hintergrundfarbe sitzt.

    python3 -m pip install pillow
    python3 tools/make-app-icons.py

Ohne `--write` wird nur berichtet, was sich ändern würde.

Vorher lief das als GitHub-Actions-Workflow, der selbst committet hat. Als
Skript ist es nachvollziehbar, lokal ausführbar und braucht keine
Schreibrechte auf das Repository.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAC_SET = ROOT / "native/Nori-macOS/Nori/Assets.xcassets/AppIcon.appiconset"
IOS_SET = ROOT / "native/Nori-iOS/Nori/Assets.xcassets/AppIcon.appiconset"
MASTER = MAC_SET / "icon.png"

MAC_OUTPUTS = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon.png": 1024,
}


def edge_color(image) -> tuple[int, int, int]:
    """Mittlere Farbe der Randpixel — der Untergrund des Icons."""
    width, height = image.size
    step = max(1, width // 64)
    samples = []
    for x in range(0, width, step):
        samples.append(image.getpixel((x, 0)))
        samples.append(image.getpixel((x, height - 1)))
    for y in range(0, height, step):
        samples.append(image.getpixel((0, y)))
        samples.append(image.getpixel((width - 1, y)))
    opaque = [s for s in samples if len(s) < 4 or s[3] > 200]
    if not opaque:
        return (0, 0, 0)
    count = len(opaque)
    return tuple(sum(s[i] for s in opaque) // count for i in range(3))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="Dateien tatsächlich schreiben.")
    args = parser.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("Pillow fehlt: python3 -m pip install pillow", file=sys.stderr)
        return 2

    if not MASTER.exists():
        print(f"Master fehlt: {MASTER}", file=sys.stderr)
        return 2

    master = Image.open(MASTER).convert("RGBA")
    if master.size != (1024, 1024):
        print(f"Master ist {master.size}, erwartet 1024×1024 — wird skaliert.")
        master = master.resize((1024, 1024), Image.Resampling.LANCZOS)

    plan: list[tuple[Path, str]] = []

    for filename, size in MAC_OUTPUTS.items():
        target = MAC_SET / filename
        if target == MASTER:
            # Der Master wird nicht neu geschrieben: ein erneutes Kodieren
            # ändert die Datei byteweise, ohne dass sich das Bild ändert.
            plan.append((target, f"macOS {size}×{size} RGBA (Master, unverändert)"))
            continue
        plan.append((target, f"macOS {size}×{size} RGBA"))
        if args.write:
            master.resize((size, size), Image.Resampling.LANCZOS).save(target)

    background = edge_color(master)
    ios_target = IOS_SET / "icon.png"
    plan.append((ios_target, f"iOS 1024×1024 RGB auf {background}"))
    if args.write:
        flat = Image.new("RGB", (1024, 1024), background)
        flat.paste(master, (0, 0), master)
        flat.save(ios_target)

    for target, description in plan:
        print(f"{'geschrieben' if args.write else 'würde schreiben'}: {target.relative_to(ROOT)} — {description}")

    # Gegenprobe: Jede in Contents.json eingetragene Datei muss existieren.
    for label, folder in (("macOS", MAC_SET), ("iOS", IOS_SET)):
        entries = json.loads((folder / "Contents.json").read_text()).get("images", [])
        missing = [e["filename"] for e in entries if e.get("filename") and not (folder / e["filename"]).exists()]
        if missing:
            print(f"WARN: {label}: in Contents.json eingetragen, aber nicht vorhanden: {missing}", file=sys.stderr)

    if not args.write:
        print("\nNichts geschrieben. Mit --write ausführen.")
    else:
        print("\nDanach: python3 tools/check-apple-sources.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
