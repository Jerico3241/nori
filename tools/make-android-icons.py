#!/usr/bin/env python3
"""Erzeugt die Android-Launcher-Icons aus demselben Master wie Apple.

Master ist `native/Nori-macOS/Nori/Assets.xcassets/AppIcon.appiconset/icon.png`
in 1024×1024 — dieselbe Datei, aus der `tools/make-app-icons.py` die
Apple-Sets baut. Ein eigenes Android-Icon zu zeichnen hieße, zwei Marken zu
pflegen.

Android will zwei Dinge:

1. **Adaptives Icon.** Die Fläche ist 108 dp, sichtbar ist je nach Hersteller
   nur der innere Kreis oder das innere Quadrat von 72 dp. Der Vordergrund
   wird deshalb auf 72/108 eingerückt; ohne das schneidet ein rundes
   Startmenü die Ränder des Icons ab.
2. **Klassisches Icon** für alles, was das adaptive nicht auswertet.

Der Hintergrund ist keine geratene Farbe, sondern der Mittelwert der
Randpixel des Masters — genau wie beim iOS-Icon.

    python3 tools/make-android-icons.py
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow fehlt:  python3 -m pip install pillow", file=sys.stderr)
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "native/Nori-macOS/Nori/Assets.xcassets/AppIcon.appiconset/icon.png"
RES = ROOT / "native/Nori-Android/app/src/main/res"

# Klassisches Icon: die Kantenlänge in Pixeln je Dichte.
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
# Adaptives Icon: 108 dp Fläche, also 2,25× der klassischen Größe.
ADAPTIVE = {name: round(size * 108 / 48) for name, size in LEGACY.items()}
# Der sichtbare Bereich eines adaptiven Icons.
SAFE = 72 / 108


def edge_color(image: Image.Image) -> tuple[int, int, int]:
    """Mittelwert der Randpixel — der Untergrund, auf dem das Icon sitzt."""
    rgb = image.convert("RGB")
    width, height = rgb.size
    pixels = []
    for x in range(0, width, max(1, width // 64)):
        pixels.append(rgb.getpixel((x, 0)))
        pixels.append(rgb.getpixel((x, height - 1)))
    for y in range(0, height, max(1, height // 64)):
        pixels.append(rgb.getpixel((0, y)))
        pixels.append(rgb.getpixel((width - 1, y)))
    count = len(pixels)
    return tuple(sum(channel[i] for channel in pixels) // count for i in range(3))


def write_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG")
    print(f"  {path.relative_to(ROOT)}  {image.width}×{image.height}")


def main() -> int:
    if not MASTER.is_file():
        print(f"Master fehlt: {MASTER}", file=sys.stderr)
        return 1

    master = Image.open(MASTER).convert("RGBA")
    background = edge_color(master)
    print(f"Untergrund aus den Randpixeln: rgb{background}")

    print("Adaptiver Vordergrund:")
    for density, size in ADAPTIVE.items():
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        inner = round(size * SAFE)
        scaled = master.resize((inner, inner), Image.LANCZOS)
        offset = (size - inner) // 2
        canvas.paste(scaled, (offset, offset), scaled)
        write_png(canvas, RES / f"mipmap-{density}/ic_launcher_foreground.png")

    print("Klassisches Icon:")
    for density, size in LEGACY.items():
        flat = Image.new("RGBA", (size, size), background + (255,))
        scaled = master.resize((size, size), Image.LANCZOS)
        flat.paste(scaled, (0, 0), scaled)
        write_png(flat.convert("RGB").convert("RGBA"), RES / f"mipmap-{density}/ic_launcher.png")
        write_png(flat.convert("RGB").convert("RGBA"), RES / f"mipmap-{density}/ic_launcher_round.png")

    colors = RES / "values/ic_launcher_background.xml"
    colors.parent.mkdir(parents=True, exist_ok=True)
    colors.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Erzeugt von tools/make-android-icons.py aus den Randpixeln des Masters. -->\n"
        "<resources>\n"
        f'    <color name="ic_launcher_background">#FF{background[0]:02X}{background[1]:02X}{background[2]:02X}</color>\n'
        "</resources>\n"
    )
    print(f"  {colors.relative_to(ROOT)}")

    for name in ("ic_launcher", "ic_launcher_round"):
        path = RES / f"mipmap-anydpi-v26/{name}.xml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_foreground" />\n'
            "</adaptive-icon>\n"
        )
        print(f"  {path.relative_to(ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
