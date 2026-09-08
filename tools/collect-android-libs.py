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
import json
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

    Drei Quellen, und die Reihenfolge ist keine Kosmetik:

    1. Das SDK-Bündel. Dort liegt die Swift-Laufzeit.
    2. Was die `swift-sdk.json` des Bündels als Sysroot nennt. Das ist in der
       Regel ein **Verweis** auf das NDK — und genau dort liegt
       `libc++_shared.so`, die im Bündel selbst fehlt.
    3. `ANDROID_NDK_HOME`, falls gesetzt.

    Punkt 2 ist der, der einmal gefehlt hat: `libc++_shared.so` gehört zum
    NDK, nicht zu Swift, und ohne sie lädt keine der Swift-Bibliotheken.
    """
    roots: list[Path] = []

    def add(path: Path | None) -> None:
        if path is None:
            return
        resolved = path.expanduser()
        if resolved.is_dir() and resolved not in roots:
            roots.append(resolved)

    bundles = Path.home() / ".swiftpm" / "swift-sdks"
    add(bundles)

    # Das Sysroot steht in der Beschreibung des SDK und ist dort relativ
    # angegeben.
    if bundles.is_dir():
        for description in bundles.rglob("swift-sdk.json"):
            try:
                data = json.loads(description.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            for target in (data.get("targetTriples") or {}).values():
                for key in ("sdkRootPath", "swiftResourcesPath", "swiftStaticResourcesPath"):
                    value = target.get(key)
                    if isinstance(value, str):
                        add((description.parent / value).resolve())
                for key in ("includeSearchPaths", "librarySearchPaths"):
                    for value in target.get(key) or []:
                        add((description.parent / value).resolve())

    for variable in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        value = os.environ.get(variable)
        if value:
            add(Path(value))

    return roots


def index_libraries(arch: str) -> dict[str, Path]:
    """Alle `.so` des SDK für diese Architektur, Name -> Pfad."""
    aliases = ARCH_ALIASES[arch]
    found: dict[str, Path] = {}
    for root in sdk_roots():
        # `os.walk` mit `followlinks` statt `Path.rglob`: das NDK-Sysroot
        # hängt als symbolischer Verweis im Bündel, und `rglob` geht daran
        # vorbei. Genau dort liegt libc++_shared.so.
        for folder, _, files in os.walk(root, followlinks=True):
            lowered = folder.lower()
            for name in files:
                if not name.endswith(".so"):
                    continue
                if not any(alias in lowered for alias in aliases):
                    continue
                # Erster Fund gewinnt; die Bündel legen dieselbe Datei teils
                # mehrfach ab (einmal im Sysroot, einmal daneben).
                found.setdefault(name, Path(folder) / name)
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
            f"{abi}: diese Abhängigkeiten fehlen und sind keine "
            f"Android-Systembibliotheken: {', '.join(sorted(set(missing)))}.\n"
            "Ohne sie startet die App auf dem Gerät nicht.\n"
            "Durchsucht wurde:\n  " + "\n  ".join(str(r) for r in sdk_roots()) + "\n"
            "libc++_shared.so gehört zum NDK, nicht zu Swift. Fehlt sie, ist "
            "das Sysroot des SDK nicht eingerichtet (siehe docs/android.md) "
            "oder ANDROID_NDK_HOME muss gesetzt sein."
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
