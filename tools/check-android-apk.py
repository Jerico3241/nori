#!/usr/bin/env python3
"""Prüft die gebaute Release-APK auf das, was ein Build nicht zeigt.

Ein grüner Gradle-Lauf beweist genau eine Sache: dass Kotlin übersetzt. Er
beweist **nicht**, dass die App auf einem Gerät startet. Drei Dinge gehen
regelmäßig genau hier verloren, und alle drei fallen erst auf dem Gerät auf:

1. **Die native Bibliothek fehlt für eine ABI.** Die APK installiert sich,
   und `System.loadLibrary` scheitert.
2. **Die Swift-Laufzeit fehlt.** Dieselbe Wirkung, andere Ursache: auf Android
   ist sie kein Systembestandteil.
3. **R8 hat die JNI-Methode entfernt.** Sie hat in Kotlin keinen Aufrufer —
   der steht in C. Ohne Keep-Regel verschwindet sie im Release-Build, und die
   App stirbt beim ersten Aufruf an „no implementation found".

Zusätzlich wird im ELF nachgesehen, ob die Symbole wirklich exportiert sind
und ob der JNI-Name zu Paket und Klasse auf der Kotlin-Seite passt. Ein
Tippfehler dort ist zur Übersetzungszeit unsichtbar.

    python3 tools/check-android-apk.py
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from elf import Elf  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
APK_DIR = ROOT / "native/Nori-Android/app/build/outputs/apk/release"

ABIS = ("arm64-v8a", "x86_64")

# Was Android selbst mitbringt — dieselbe Liste wie in
# tools/collect-android-libs.py, und aus demselben Grund.
SYSTEM = {
    "libc.so", "libm.so", "libdl.so", "libstdc++.so", "liblog.so",
    "libandroid.so", "libz.so", "libGLESv2.so", "libEGL.so", "libjnigraphics.so",
    "libOpenSLES.so", "libaaudio.so", "libmediandk.so", "libnativewindow.so",
    "libvulkan.so", "libcamera2ndk.so", "libneuralnetworks.so", "libicuuc.so",
    "libicui18n.so",
}

# Muss zu `de.nori.core.NoriBridge.nativeCall` passen.
JNI_SYMBOL = "Java_de_nori_core_NoriBridge_nativeCall"
C_SYMBOLS = ("nori_bridge_call", "nori_bridge_free")

problems: list[str] = []


def fail(message: str) -> None:
    problems.append(message)


def check_apk(apk: Path) -> set[str]:
    """Eine APK prüfen. Gibt die enthaltenen ABIs zurück."""
    print(f"\n{apk.name}  ({apk.stat().st_size / 1_048_576:.1f} MB)")
    contained: set[str] = set()

    with zipfile.ZipFile(apk) as archive:
        entries = set(archive.namelist())

        for abi in ABIS:
            present = {
                name.rsplit("/", 1)[-1]
                for name in entries
                if name.startswith(f"lib/{abi}/") and name.endswith(".so")
            }
            if not present:
                continue
            contained.add(abi)

            if "libNoriAndroid.so" not in present:
                fail(f"{apk.name}: lib/{abi}/libNoriAndroid.so fehlt — dort startet die App nicht.")
                continue

            try:
                core = Elf(archive.read(f"lib/{abi}/libNoriAndroid.so"))
            except ValueError:
                fail(f"{apk.name}: lib/{abi}/libNoriAndroid.so ließ sich nicht als ELF lesen.")
                continue

            symbols = core.dynamic_symbols()
            if JNI_SYMBOL not in symbols:
                fail(
                    f"{apk.name} ({abi}): {JNI_SYMBOL} wird nicht exportiert. Der Name "
                    "muss zu Paket und Klasse von NoriBridge.kt passen."
                )
            for symbol in C_SYMBOLS:
                if symbol not in symbols:
                    fail(f"{apk.name} ({abi}): {symbol} fehlt (@_cdecl in NoriBridge.swift).")

            # Derselbe Maßstab, den der Lader auf dem Gerät anlegt: jede
            # Abhängigkeit jeder mitgelieferten Bibliothek muss auffindbar
            # sein. Eine fehlende reicht, damit die App nicht startet.
            for name in sorted(present):
                try:
                    needed = Elf(archive.read(f"lib/{abi}/{name}")).needed()
                except ValueError:
                    fail(f"{apk.name}: {abi}/{name} ließ sich nicht als ELF lesen.")
                    continue
                for dependency in needed:
                    if dependency in SYSTEM or dependency in present:
                        continue
                    fail(
                        f"{apk.name} ({abi}): {name} braucht {dependency}, das weder in "
                        "der APK liegt noch eine Android-Systembibliothek ist."
                    )

            print(f"  {abi}: {len(present)} Bibliotheken, {len(symbols)} Symbole, Abhängigkeiten vollständig")

        if not contained:
            fail(f"{apk.name}: enthält für keine unterstützte ABI native Bibliotheken.")

        # R8: die Kotlin-Seite der Brücke muss im DEX überlebt haben.
        dex = b"".join(archive.read(name) for name in sorted(entries) if name.endswith(".dex"))
        if not dex:
            fail(f"{apk.name}: kein DEX enthalten.")
        else:
            for needle in (b"Lde/nori/core/NoriBridge;", b"nativeCall"):
                if needle not in dex:
                    fail(
                        f"{apk.name}: {needle.decode()} fehlt im DEX — R8 hat die Brücke "
                        "entfernt. Keep-Regel in proguard-rules.pro prüfen."
                    )
            print("  DEX: NoriBridge.nativeCall vorhanden")

    return contained


def main() -> int:
    apks = sorted(APK_DIR.glob("*.apk"))
    if not apks:
        print(f"Keine Release-APK unter {APK_DIR}", file=sys.stderr)
        return 1

    covered: set[str] = set()
    for apk in apks:
        covered |= check_apk(apk)

    # Über alle APKs hinweg müssen beide Ziel-ABIs vorkommen. Sonst ist eine
    # der beiden stillschweigend aus dem Build gefallen.
    for abi in ABIS:
        if abi not in covered:
            fail(f"Keine einzige APK enthält Bibliotheken für {abi}.")

    if problems:
        print()
        for problem in problems:
            print(f"FEHLER: {problem}", file=sys.stderr)
        return 1

    print(f"\ncheck-android-apk: {len(apks)} APK(s) geprüft, Kern, Laufzeit und Brücke vorhanden.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
