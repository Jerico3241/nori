#!/usr/bin/env python3
"""Sammelt die nativen Bibliotheken für die Android-App in `jniLibs`.

Zwei Dinge müssen in die APK:

1. `libNoriAndroid.so` — NoriCore samt JNI-Hülle, je ABI einmal.
2. Die **Swift-Laufzeit**. Sie ist auf Android kein Systembestandteil.
   Fehlt sie, startet die App auf einem sauberen Gerät nicht, sondern
   stirbt beim `System.loadLibrary` an „library libswiftCore.so not found" —
   ein Fehler, der auf dem Entwicklerrechner nie auftritt.

Die Laufzeit liegt im Swift-SDK-Bundle. Dessen Verzeichnisaufbau hat sich
zwischen den Swift-Fassungen mehrfach geändert, deshalb wird hier gesucht und
nicht geraten: alle `.so` unterhalb der installierten SDKs, zugeordnet über
die Architektur im Pfad. Was fehlt, wird beim Namen genannt — eine stumme
unvollständige APK ist teurer als ein roter Lauf.
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

# Verzeichnisname in der APK je Ziel-Tripel-Präfix.
ABI_BY_ARCH = {
    "aarch64": "arm64-v8a",
    "x86_64": "x86_64",
}

# Wie die Architektur in den Pfaden des SDK-Bundles auftaucht.
ARCH_ALIASES = {
    "aarch64": ("aarch64", "arm64-v8a", "arm64"),
    "x86_64": ("x86_64", "x86-64"),
}

# Die Laufzeit, die eine mit SwiftPM gebaute Android-Bibliothek zieht.
# `libc++_shared.so` kommt aus dem NDK und wird von der Swift-Laufzeit
# gebraucht; ohne sie bricht das Laden mit derselben Meldung ab.
RUNTIME = [
    "libswiftCore.so",
    "libswiftAndroid.so",
    "libswift_Concurrency.so",
    "libswift_StringProcessing.so",
    "libswift_RegexParser.so",
    "libswiftSynchronization.so",
    "libFoundation.so",
    "libFoundationEssentials.so",
    "libFoundationInternationalization.so",
    "libFoundationNetworking.so",
    "libFoundationXML.so",
    "lib_FoundationICU.so",
    "lib_FoundationCShims.so",
    "libdispatch.so",
    "libswiftDispatch.so",
    "libBlocksRuntime.so",
    "libandroid-execinfo.so",
    "libc++_shared.so",
]

# Ohne diese startet gar nichts. Der Rest ist je nach Swift-Fassung
# vorhanden oder in eine andere Bibliothek eingegangen.
REQUIRED = {
    "libswiftCore.so",
    "libFoundation.so",
    "libFoundationNetworking.so",
    "libswift_Concurrency.so",
    "libc++_shared.so",
}


def arch_of(triple: str) -> str:
    arch = triple.split("-", 1)[0]
    if arch not in ABI_BY_ARCH:
        raise SystemExit(f"Unbekannte Architektur im Tripel '{triple}'.")
    return arch


def sdk_roots() -> list[Path]:
    roots = [Path.home() / ".swiftpm" / "swift-sdks"]
    return [root for root in roots if root.is_dir()]


def find_runtime(arch: str) -> dict[str, Path]:
    """Alle Laufzeitbibliotheken dieser Architektur, Name -> Pfad."""
    aliases = ARCH_ALIASES[arch]
    found: dict[str, Path] = {}
    for root in sdk_roots():
        for path in root.rglob("*.so"):
            if path.name not in RUNTIME:
                continue
            parts = {part.lower() for part in path.parts}
            if not any(alias in part for alias in aliases for part in parts):
                continue
            # Erster Fund gewinnt; die SDKs legen dieselbe Datei teils
            # mehrfach ab (einmal im Sysroot, einmal daneben).
            found.setdefault(path.name, path)
    return found


def copy_abi(build: Path, triple: str, out: Path) -> None:
    arch = arch_of(triple)
    abi = ABI_BY_ARCH[arch]
    target = out / abi
    target.mkdir(parents=True, exist_ok=True)

    library = build / triple / "release" / "libNoriAndroid.so"
    if not library.is_file():
        candidates = sorted(str(p) for p in build.rglob("libNoriAndroid.so"))
        raise SystemExit(
            f"{abi}: libNoriAndroid.so nicht unter {library}.\n"
            + ("Gefunden wurde:\n  " + "\n  ".join(candidates) if candidates else "Nichts gebaut.")
        )
    shutil.copy2(library, target / library.name)
    print(f"{abi}: {library.name}")

    runtime = find_runtime(arch)
    for name in RUNTIME:
        path = runtime.get(name)
        if path is None:
            continue
        shutil.copy2(path, target / name)
        print(f"{abi}: {name}  <- {path}")

    missing = sorted(REQUIRED - set(runtime))
    if missing:
        raise SystemExit(
            f"{abi}: Swift-Laufzeit unvollständig, es fehlen: {', '.join(missing)}.\n"
            f"Durchsucht wurde: {', '.join(str(r) for r in sdk_roots()) or '(kein SDK gefunden)'}\n"
            "Ohne diese Dateien startet die App auf dem Gerät nicht."
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arm64-build", type=Path, required=True)
    parser.add_argument("--x86-64-build", type=Path, required=True)
    parser.add_argument("--arm64-triple", required=True)
    parser.add_argument("--x86-64-triple", required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    if args.out.exists():
        shutil.rmtree(args.out)

    copy_abi(args.arm64_build, args.arm64_triple, args.out)
    copy_abi(args.x86_64_build, args.x86_64_triple, args.out)

    total = sum(1 for _ in args.out.rglob("*.so"))
    print(f"\n{total} Bibliotheken in {args.out}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
