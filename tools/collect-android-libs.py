#!/usr/bin/env python3
"""Sammelt die nativen Bibliotheken für die Android-App in `jniLibs`.

`libNoriAndroid.so` allein reicht nicht. Sie zieht die **Swift-Laufzeit** nach,
und die ist auf Android kein Systembestandteil: fehlt sie, stirbt die App beim
`System.loadLibrary` an „library libswiftCore.so not found" — ein Fehler, der
auf dem Entwicklerrechner nie auftritt, weil dort nichts geladen wird.

Welche Dateien das genau sind, wird hier **nicht geraten**. Eine gepflegte
Namensliste geht früher oder später schief: die Swift-Fassungen verschieben
ständig etwas zwischen `libFoundation`, `libFoundationEssentials` und
`libFoundationNetworking`, und je nach Bündel liegen `libcurl`, `libcrypto`,
`libssl` und `libxml2` daneben statt eingebaut. Stattdessen werden die
`DT_NEEDED`-Einträge der gebauten Bibliothek gelesen und rekursiv aufgelöst —
also genau das, was der Lader auf dem Gerät auch tun wird.

    python3 tools/collect-android-libs.py \\
        --arm64-build … --x86-64-build … \\
        --arm64-triple … --x86-64-triple … \\
        --out …/jniLibs
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from elf import Elf  # noqa: E402

ABI_BY_ARCH = {"aarch64": "arm64-v8a", "x86_64": "x86_64"}
ARCH_ALIASES = {
    "aarch64": ("aarch64", "arm64-v8a", "arm64"),
    "x86_64": ("x86_64", "x86-64"),
}

# Was Android selbst mitbringt. Alles andere muss in die APK.
#
# `libc++_shared.so` steht bewusst **nicht** hier: die gibt es auf dem Gerät
# nicht, sie kommt aus dem NDK und wird mitgeliefert.
SYSTEM = {
    "libc.so", "libm.so", "libdl.so", "libstdc++.so", "liblog.so",
    "libandroid.so", "libz.so", "libGLESv2.so", "libEGL.so", "libjnigraphics.so",
    "libOpenSLES.so", "libaaudio.so", "libmediandk.so", "libnativewindow.so",
    "libvulkan.so", "libcamera2ndk.so", "libneuralnetworks.so", "libicuuc.so",
    "libicui18n.so",
}


def sdk_roots() -> list[Path]:
    """Wo nach Bibliotheken gesucht wird.

    Das SDK-Bündel richtet sich beim Einrichten ein `ndk-sysroot` ein und hat
    damit in der Regel auch `libc++_shared.so`. Ist ANDROID_NDK_HOME gesetzt,
    wird das NDK zusätzlich durchsucht — dann fehlt sie auch dann nicht, wenn
    das Bündel anders aufgebaut ist als erwartet.
    """
    candidates = [Path.home() / ".swiftpm" / "swift-sdks"]
    ndk = os.environ.get("ANDROID_NDK_HOME") or os.environ.get("ANDROID_NDK_ROOT")
    if ndk:
        candidates.append(Path(ndk))
    return [path for path in candidates if path.is_dir()]


def index_libraries(arch: str) -> dict[str, Path]:
    """Alle `.so` des SDK für diese Architektur, Name -> Pfad."""
    aliases = ARCH_ALIASES[arch]
    found: dict[str, Path] = {}
    for root in sdk_roots():
        for path in root.rglob("*.so"):
            parts = [part.lower() for part in path.parts]
            if not any(alias in part for alias in aliases for part in parts):
                continue
            # Erster Fund gewinnt; die Bündel legen dieselbe Datei teils
            # mehrfach ab (einmal im Sysroot, einmal daneben).
            found.setdefault(path.name, path)
    return found


def collect(build: Path, triple: str, out: Path) -> None:
    arch = triple.split("-", 1)[0]
    if arch not in ABI_BY_ARCH:
        raise SystemExit(f"Unbekannte Architektur im Tripel '{triple}'.")
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

    available = index_libraries(arch)
    if not available:
        raise SystemExit(
            f"{abi}: im Swift-SDK wurde keine einzige .so für {arch} gefunden.\n"
            f"Durchsucht: {', '.join(str(r) for r in sdk_roots()) or '(kein SDK installiert)'}"
        )

    shutil.copy2(library, target / library.name)
    print(f"{abi}: {library.name}")

    # Rekursiv aufloesen, genau wie der Lader auf dem Geraet.
    done: set[str] = {library.name}
    missing: list[str] = []
    queue = list(Elf.load(library).needed())

    while queue:
        name = queue.pop(0)
        if name in done or name in SYSTEM:
            done.add(name)
            continue
        source = available.get(name)
        if source is None:
            missing.append(name)
            done.add(name)
            continue
        shutil.copy2(source, target / name)
        done.add(name)
        print(f"{abi}: {name}  <- {source}")
        queue.extend(Elf.load(source).needed())

    if missing:
        raise SystemExit(
            f"{abi}: diese Abhängigkeiten fehlen im SDK und sind keine "
            f"Android-Systembibliotheken: {', '.join(sorted(set(missing)))}.\n"
            "Ohne sie startet die App auf dem Gerät nicht. Entweder liegen sie "
            "woanders im Bündel, oder sie gehören in die Liste SYSTEM in "
            "diesem Skript."
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

    collect(args.arm64_build, args.arm64_triple, args.out)
    collect(args.x86_64_build, args.x86_64_triple, args.out)

    total = sum(1 for _ in args.out.rglob("*.so"))
    print(f"\n{total} Bibliotheken in {args.out}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
