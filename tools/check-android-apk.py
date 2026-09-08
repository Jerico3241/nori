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

import struct
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APK_DIR = ROOT / "native/Nori-Android/app/build/outputs/apk/release"

ABIS = ("arm64-v8a", "x86_64")

# Ohne diese startet die App nicht.
RUNTIME = ("libswiftCore.so", "libFoundation.so", "libFoundationNetworking.so", "libc++_shared.so")

# Muss zu `de.nori.core.NoriBridge.nativeCall` passen.
JNI_SYMBOL = "Java_de_nori_core_NoriBridge_nativeCall"
C_SYMBOLS = ("nori_bridge_call", "nori_bridge_free")

problems: list[str] = []


def fail(message: str) -> None:
    problems.append(message)


def elf_dynamic_symbols(data: bytes) -> set[str]:
    """Die exportierten Namen einer ELF-Bibliothek.

    Bewusst ohne Fremdbibliothek: `nm` gibt es auf dem Runner nicht
    zwangsläufig für Android-Binärdateien, und der benötigte Teil des Formats
    ist überschaubar — Sektionstabelle lesen, `.dynsym` und `.dynstr` finden,
    Namen einsammeln.
    """
    if data[:4] != b"\x7fELF":
        return set()
    is_64 = data[4] == 2
    little = data[5] == 1
    end = "<" if little else ">"

    if is_64:
        e_shoff, = struct.unpack_from(end + "Q", data, 0x28)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(end + "HHH", data, 0x3A)
    else:
        e_shoff, = struct.unpack_from(end + "I", data, 0x20)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from(end + "HHH", data, 0x2E)

    sections = []
    for index in range(e_shnum):
        base = e_shoff + index * e_shentsize
        if is_64:
            name, sh_type = struct.unpack_from(end + "II", data, base)
            offset, size = struct.unpack_from(end + "QQ", data, base + 0x18)
            link, = struct.unpack_from(end + "I", data, base + 0x28)
            entsize, = struct.unpack_from(end + "Q", data, base + 0x38)
        else:
            name, sh_type = struct.unpack_from(end + "II", data, base)
            offset, size = struct.unpack_from(end + "II", data, base + 0x10)
            link, = struct.unpack_from(end + "I", data, base + 0x18)
            entsize, = struct.unpack_from(end + "I", data, base + 0x24)
        sections.append((name, sh_type, offset, size, link, entsize))

    # SHT_DYNSYM = 11
    names: set[str] = set()
    for _, sh_type, offset, size, link, entsize in sections:
        if sh_type != 11 or entsize == 0 or link >= len(sections):
            continue
        _, _, str_offset, str_size, _, _ = sections[link]
        strtab = data[str_offset:str_offset + str_size]
        for position in range(offset, offset + size, entsize):
            st_name, = struct.unpack_from(end + "I", data, position)
            if st_name == 0 or st_name >= len(strtab):
                continue
            terminator = strtab.find(b"\0", st_name)
            names.add(strtab[st_name:terminator].decode("utf-8", "replace"))
    return names


def main() -> int:
    apks = sorted(APK_DIR.glob("*.apk"))
    if not apks:
        print(f"Keine Release-APK unter {APK_DIR}", file=sys.stderr)
        return 1
    apk = apks[0]
    print(f"Geprüft wird: {apk.relative_to(ROOT)}  ({apk.stat().st_size / 1_048_576:.1f} MB)")

    with zipfile.ZipFile(apk) as archive:
        entries = set(archive.namelist())

        for abi in ABIS:
            library = f"lib/{abi}/libNoriAndroid.so"
            if library not in entries:
                fail(f"{library} fehlt in der APK — auf {abi} startet die App nicht.")
                continue

            for name in RUNTIME:
                if f"lib/{abi}/{name}" not in entries:
                    fail(f"lib/{abi}/{name} fehlt — die Swift-Laufzeit ist unvollständig.")

            symbols = elf_dynamic_symbols(archive.read(library))
            if not symbols:
                fail(f"{library} ließ sich nicht als ELF lesen.")
                continue
            if JNI_SYMBOL not in symbols:
                fail(
                    f"{abi}: {JNI_SYMBOL} wird nicht exportiert. Der Name muss zu "
                    "Paket und Klasse von NoriBridge.kt passen."
                )
            for symbol in C_SYMBOLS:
                if symbol not in symbols:
                    fail(f"{abi}: {symbol} wird nicht exportiert (@_cdecl in NoriBridge.swift).")
            print(f"  {abi}: {len(symbols)} exportierte Symbole, Brücke vorhanden")

        # R8: die Kotlin-Seite der Brücke muss im DEX überlebt haben.
        dex = b"".join(
            archive.read(name) for name in sorted(entries) if name.endswith(".dex")
        )
        if not dex:
            fail("Kein DEX in der APK.")
        else:
            for needle in (b"Lde/nori/core/NoriBridge;", b"nativeCall"):
                if needle not in dex:
                    fail(
                        f"{needle.decode()} fehlt im DEX — R8 hat die Brücke entfernt. "
                        "Keep-Regel in proguard-rules.pro prüfen."
                    )
            if not problems:
                print("  DEX: NoriBridge.nativeCall vorhanden")

    if problems:
        print()
        for problem in problems:
            print(f"FEHLER: {problem}", file=sys.stderr)
        return 1

    print("\ncheck-android-apk: APK enthält Kern, Laufzeit und Brücke.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
