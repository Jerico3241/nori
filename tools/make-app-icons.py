#!/usr/bin/env python3
"""Erzeugt beide App-Icon-Sets aus einem einzigen Master.

Master ist `assets/branding/nori-app-icon.png` — das offizielle Nori-Icon in
1076×1076, quadratisch und randlos. Es ist aus der gelieferten Vorlage
(1254×1254) geschnitten: die zeigte die Kachel als Mockup, mit Schlagschatten
auf einem etwas helleren Grund. Zugeschnitten wurde auf die Kachel selbst
(Rechteck 89…1165, zwei Punkte innerhalb der Kante), und die vier abgerundeten
Ecken wurden mit dem jeweils nächstliegenden Bildpunkt aufgefüllt. Damit liegt
das Motiv unverändert, aber ohne fremde Rundung und ohne Rand vor: Apple legt
seine eigene Maske darüber, eine zweite im Bild würde doppelt runden.

Daraus entstehen:

- macOS: alle von `Contents.json` verlangten Größen, RGBA (Alphakanal erlaubt
  und erwünscht — macOS-Icons sind abgerundet und dürfen transparente Ecken
  haben). Das Motiv selbst ist deckend, die Ecken bleiben also gefüllt.
- iOS: ein einzelnes 1024×1024-Icon **ohne** Alphakanal. Der App-Store und der
  Asset-Catalog verlangen ein deckendes Bild; ein transparentes wird beim Bauen
  stillschweigend verworfen und der Build meldet dann nur noch
  „app icon set named 'AppIcon' did not have any applicable content".
- Windows: `desktop/icon.png` für das Electron-Fenster und `desktop/icon.ico`
  mit allen Größen, die der Explorer und die Taskleiste abfragen.
- webOS: `icon-80/130/400.png` für die Kachelübersicht und das Startbild
  `splash-1920x1080.png`. Vorher erzeugte `apps/webos/tools/make-assets.mjs`
  dort ein eigenes „N"; seit das offizielle Icon als Bilddatei vorliegt, gibt
  es nichts mehr nachzuzeichnen, und alle Plattformen zeigen dasselbe Motiv.

Nirgends wird eine Rundung, ein Rahmen oder ein Schatten hinzugefügt. Das
Motiv füllt die Fläche; die Form gibt das jeweilige System vor.

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
DESKTOP = ROOT / "desktop"
WEBOS = ROOT / "apps/webos/public"
MASTER = ROOT / "assets/branding/nori-app-icon.png"

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

# Was Explorer, Taskleiste und Alt-Tab unter Windows aus der .ico ziehen.
ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]

WEBOS_OUTPUTS = {"icon-80.png": 80, "icon-130.png": 130, "icon-400.png": 400}

# Das Startbild von webOS: der dunkle Grund der App, das Symbol mittig.
# Maße und Sitz wie bisher — nur das Symbol ist jetzt das echte.
SPLASH_SIZE = (1920, 1080)
SPLASH_BACKGROUND = (0x05, 0x06, 0x0a)
SPLASH_MARK = 0.19      # Kantenlänge des Symbols, Anteil der Höhe
SPLASH_CENTRE = 0.44    # Mitte des Symbols, Anteil der Höhe


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
    if master.width != master.height:
        print(f"Master ist {master.size} und damit nicht quadratisch.", file=sys.stderr)
        return 2
    if master.width < 1024:
        print(f"Master ist nur {master.width} Punkte breit; 1024 sind das Minimum.", file=sys.stderr)
        return 2

    plan: list[tuple[Path, str]] = []

    for filename, size in MAC_OUTPUTS.items():
        target = MAC_SET / filename
        plan.append((target, f"macOS {size}×{size} RGBA"))
        if args.write:
            master.resize((size, size), Image.Resampling.LANCZOS).save(target)

    rgb = master.convert("RGB")

    for filename, size in WEBOS_OUTPUTS.items():
        target = WEBOS / filename
        plan.append((target, f"webOS {size}×{size} RGB"))
        if args.write:
            rgb.resize((size, size), Image.Resampling.LANCZOS).save(target)

    splash_target = WEBOS / "splash-1920x1080.png"
    plan.append((splash_target, f"webOS Startbild {SPLASH_SIZE[0]}×{SPLASH_SIZE[1]}"))
    if args.write:
        width, height = SPLASH_SIZE
        mark = round(height * SPLASH_MARK)
        splash = Image.new("RGB", SPLASH_SIZE, SPLASH_BACKGROUND)
        splash.paste(
            rgb.resize((mark, mark), Image.Resampling.LANCZOS),
            (round(width / 2 - mark / 2), round(height * SPLASH_CENTRE - mark / 2)),
        )
        splash.save(splash_target)

    desktop_png = DESKTOP / "icon.png"
    plan.append((desktop_png, "Windows 256×256 RGBA"))
    if args.write:
        master.resize((256, 256), Image.Resampling.LANCZOS).save(desktop_png)

    desktop_ico = DESKTOP / "icon.ico"
    plan.append((desktop_ico, "Windows .ico " + ", ".join(str(s) for s in ICO_SIZES)))
    if args.write:
        master.resize((256, 256), Image.Resampling.LANCZOS).save(
            desktop_ico, sizes=[(s, s) for s in ICO_SIZES]
        )

    background = edge_color(master)
    ios_target = IOS_SET / "icon.png"
    plan.append((ios_target, f"iOS 1024×1024 RGB auf {background}"))
    if args.write:
        scaled = master.resize((1024, 1024), Image.Resampling.LANCZOS)
        flat = Image.new("RGB", (1024, 1024), background)
        flat.paste(scaled, (0, 0), scaled)
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
