#!/usr/bin/env python3
"""Statische Prüfung der beiden Apple-Targets von Nori.

Warum das existiert: Swift lässt sich in dieser Umgebung nicht kompilieren –
der einzige echte Typechecker ist der GitHub-Actions-Lauf `Build macOS`
(~1 Minute). Dieses Skript fängt vorab die Fehlerklassen ab, die dort schon
mehrfach aufgeschlagen sind, damit nicht jeder Tippfehler eine CI-Runde kostet.

    python3 tools/check-apple-sources.py

Exit-Code 1 bei ERROR, 0 bei nur WARN. Neue Erkenntnisse aus einem roten Build
gehören als Zeile in die Tabellen unten – das Skript ist als wachsende
Lessons-learned-Liste gedacht, nicht als vollständiger Linter.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "native/Nori-iOS/Nori"
MAC = ROOT / "native/Nori-macOS/Nori"

# Dateien ohne jede plattformspezifische Zeile. Sie müssen Byte für Byte
# identisch bleiben; eine Änderung gehört immer in beide Targets.
SHARED_IDENTICAL = [
    "Models.swift",
    "LibraryStore.swift",
    "AniworldClient.swift",
    "HosterResolver.swift",
]

# Gleiche Aufgabe, aber unterschiedlich formuliert (die macOS-Fassung wurde
# umgebaut, um Typechecker-Timeouts zu vermeiden). Byte-Gleichheit ist hier
# nicht zu erwarten – wohl aber die gleiche Menge an Deklarationen.
SHARED_STRUCTURE = ["HTML.swift"]

# APIs, die es schlicht nicht gibt. Jede Zeile hier hat einmal einen Build
# gekostet.
NONEXISTENT = {
    r"\\\.openSettings": (
        "EnvironmentValues.openSettings existiert nicht. "
        "Für einen Knopf, der die Einstellungen öffnet: SettingsLink (macOS 14+)."
    ),
}

# Symbole, die neuer sind als das Deployment-Target des jeweiligen Targets.
TOO_NEW_MACOS_14 = {
    r"\.tabViewStyle\(\.sidebarAdaptable\)": "macOS 15",
    r"\.toolbar\(removing:": "macOS 15",
    r"\bTabSection\b": "macOS 15",
    r"\.searchFocused\(": "macOS 15",
    r"\.windowResizability\(\.automatic\)": "macOS 15",
    r"\bGlassEffectContainer\b": "macOS 26",
    r"\.glassEffect\(": "macOS 26",
}

# Frameworks/Typen, die im jeweils anderen Target nicht existieren.
UIKIT_ONLY = r"\b(UIKit|UIApplication|UIImage|UIColor|UIScreen|UIDevice|UIViewRepresentable|UIViewControllerRepresentable|UIPasteboard)\b"
APPKIT_ONLY = r"\b(AppKit|NSApplication|NSApp|NSImage|NSColor|NSWindow|NSViewRepresentable|NSPasteboard|NSWorkspace)\b"

# Kompiliert auf macOS, tut dort aber nichts oder sieht falsch aus.
INEFFECTIVE_ON_MACOS = {
    r"\.refreshable\s*\{": "Pull-to-Refresh gibt es auf macOS nicht – stattdessen einen Aktualisieren-Knopf in die Toolbar.",
    r"\.navigationBarTitleDisplayMode\(": "iOS-only; auf macOS ohne Wirkung.",
    r"\.navigationBarBackButtonHidden\(": "iOS-only; auf macOS ohne Wirkung.",
    r"\.fullScreenCover\(": "iOS-only; auf macOS ein eigenes Fenster (Window-Scene) verwenden.",
    r"\.listRowBackground\(": "Übermalt die native Auswahlmarkierung; auf macOS listStyle(.inset(alternatesRowBackgrounds:)) bevorzugen.",
    r"\.preferredColorScheme\(": "Erzwingt ein Erscheinungsbild und ignoriert die Systemeinstellung.",
}

DECL = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|internal\s+|fileprivate\s+|static\s+|final\s+)*"
    r"(?:struct|class|enum|extension|func|actor|protocol)\s+([A-Za-z_]\w*)",
    re.M,
)

problems: list[tuple[str, str, str]] = []


def add(level: str, where: str, message: str) -> None:
    problems.append((level, where, message))


def swift_files(folder: Path) -> list[Path]:
    return sorted(folder.glob("*.swift"))


def strip_comments_and_strings(src: str) -> str:
    """Grobe Bereinigung, damit Treffer in Kommentaren keine Fehlalarme geben."""
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    return src


def check_shared_files() -> None:
    for name in SHARED_IDENTICAL:
        a, b = IOS / name, MAC / name
        if not a.exists() or not b.exists():
            add("ERROR", name, "Datei fehlt in einem der beiden Targets.")
            continue
        if a.read_bytes() != b.read_bytes():
            add(
                "ERROR",
                name,
                "Gemeinsame Datei weicht zwischen iOS und macOS ab. "
                "Änderungen an Modellen, Store, Client und Resolver gehören in beide Targets "
                f"(Vergleich: diff native/Nori-iOS/Nori/{name} native/Nori-macOS/Nori/{name}).",
            )

    for name in SHARED_STRUCTURE:
        a, b = IOS / name, MAC / name
        if not a.exists() or not b.exists():
            add("ERROR", name, "Datei fehlt in einem der beiden Targets.")
            continue
        da = set(DECL.findall(a.read_text()))
        db = set(DECL.findall(b.read_text()))
        for missing in sorted(da - db):
            add("ERROR", name, f"`{missing}` gibt es nur im iOS-Target.")
        for missing in sorted(db - da):
            add("ERROR", name, f"`{missing}` gibt es nur im macOS-Target.")


def check_target(folder: Path, *, is_mac: bool) -> None:
    label = "macOS" if is_mac else "iOS"
    wrong_framework = UIKIT_ONLY if is_mac else APPKIT_ONLY
    other = "UIKit" if is_mac else "AppKit"

    for path in swift_files(folder):
        raw = path.read_text()
        src = strip_comments_and_strings(raw)
        where = f"{label}/{path.name}"

        for match in re.finditer(wrong_framework, src):
            add("ERROR", where, f"`{match.group(1)}` stammt aus {other} und existiert im {label}-Target nicht.")

        for pattern, hint in NONEXISTENT.items():
            if re.search(pattern, src):
                add("ERROR", where, hint)

        if is_mac:
            for pattern, since in TOO_NEW_MACOS_14.items():
                if re.search(pattern, src):
                    add("ERROR", where, f"Braucht {since}, das Target ist auf macOS 14.0 festgelegt.")
            for pattern, hint in INEFFECTIVE_ON_MACOS.items():
                if re.search(pattern, src):
                    add("WARN", where, hint)
            # .tabItem ist im Settings-Fenster die übliche Bauform, in der
            # Hauptnavigation dagegen ein iOS-Import.
            if path.name != "SettingsView.swift" and re.search(r"\.tabItem\s*\{", src):
                add("WARN", where, "TabView/.tabItem als Hauptnavigation ist iOS-Bauform; auf macOS NavigationSplitView mit Seitenleiste.")


def check_section_initializers(folder: Path, label: str) -> None:
    """`Section("Titel") { … } footer: { … }` gibt es in SwiftUI nicht.

    Es gibt Titel-mit-Inhalt oder Header- und Footer-Closures, aber keine
    Mischung. Der Compiler meldet dazu nur „missing argument label 'content:'",
    woraus die eigentliche Ursache nicht hervorgeht — hat einmal eine
    CI-Runde gekostet.

    Bewusst keine Klammerzählung per Regex: gesucht wird ein `Section(` mit
    Zeichenketten-Argument, dem vor dem nächsten `Section(` ein `} footer:`
    folgt.
    """
    titled = re.compile(r"Section\s*\(\s*[\"']")
    # Grenze ist jede folgende Section, auch eine titellose — sonst liest das
    # Fenster über sie hinweg und meldet deren zulässiges footer: als Fehler.
    any_section = re.compile(r"\bSection\s*[({]")
    for path in swift_files(folder):
        src = strip_comments_and_strings(path.read_text())
        for match in titled.finditer(src):
            rest = src[match.end():]
            boundary = any_section.search(rest)
            window = rest[: boundary.start()] if boundary else rest
            if re.search(r"\}\s*footer\s*:", window):
                add(
                    "ERROR",
                    f"{label}/{path.name}",
                    "Section mit Titel und footer: gibt es nicht. Entweder "
                    'Section("Titel") { … } oder '
                    "Section { … } header: { … } footer: { … }.",
                )
                break


def check_deployment_targets() -> None:
    """Die Regeln oben sind auf macOS 14 / iOS 17 geeicht."""
    expectations = [
        (ROOT / "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj", "MACOSX_DEPLOYMENT_TARGET", "14.0"),
        (ROOT / "native/Nori-iOS/Nori.xcodeproj/project.pbxproj", "IPHONEOS_DEPLOYMENT_TARGET", "17.0"),
    ]
    for pbx, key, expected in expectations:
        if not pbx.exists():
            continue
        found = set(re.findall(rf"{key}\s*=\s*([\d.]+)", pbx.read_text()))
        if found and found != {expected}:
            add(
                "WARN",
                pbx.name,
                f"{key} ist {sorted(found)}, die Regeln in diesem Skript gehen von {expected} aus. "
                "Versionsgrenzen oben anpassen.",
            )


def main() -> int:
    if not IOS.is_dir() or not MAC.is_dir():
        print("Quellordner nicht gefunden – bitte aus dem Repo-Wurzelverzeichnis aufrufen.", file=sys.stderr)
        return 2

    check_shared_files()
    check_target(IOS, is_mac=False)
    check_target(MAC, is_mac=True)
    check_section_initializers(IOS, "iOS")
    check_section_initializers(MAC, "macOS")
    check_deployment_targets()

    errors = [p for p in problems if p[0] == "ERROR"]
    warnings = [p for p in problems if p[0] == "WARN"]

    for level, where, message in errors + warnings:
        print(f"{level}: {where}: {message}")

    print()
    if not problems:
        print("check-apple-sources: keine Auffälligkeiten.")
    else:
        print(f"check-apple-sources: {len(errors)} Fehler, {len(warnings)} Hinweise.")
    print("Hinweis: ersetzt keinen Build. Der Typechecker ist der Lauf 'Build macOS'.")

    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
