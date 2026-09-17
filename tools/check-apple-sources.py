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

import json
import re
import struct
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
    # Seit dem ersten iOS-Build byte-gleich: die iOS-Fassung hatte lange
    # Optional-Ketten, an denen der Typechecker abbrach, und fehlende `try`.
    # Die macOS-Fassung hatte dieselbe Logik bereits aufgelöst.
    "HTML.swift",
    # Auswertung der HLS-Master-Playlist. Nur der iOS-Player benutzt sie
    # bisher — die Mac-Fassung spielt mit den Systemreglern —, aber sie
    # gehört zur Stream-Auswertung und liegt deshalb im gemeinsamen Kern,
    # wo `swift test` sie erreicht.
    "HLSPlaylist.swift",
    # Bildadressen und Titelzuordnung von TMDB. Beide Targets brauchen sie,
    # weil AniworldClient.swift sie benutzt; die Startseite von iOS benutzt
    # dieselbe Zuordnung, um TMDB-Ranglisten auf Noris Katalog zurückzuführen.
    "TMDBImages.swift",
    "TMDBMatcher.swift",
    # Die Katalogsuche. Der iPhone-Katalog sucht über `CatalogEntry`, der
    # Mac-Katalog über `CatalogItem` — mit derselben Normalisierung.
    "CatalogSearch.swift",
    # Der Geräteabgleich über Google Drive. Regeln, Ablauf, HTTP und OAuth
    # gehören in beide Targets gleichermaßen; nur der Anmeldeweg ist
    # plattformeigen und liegt deshalb je Target in `GoogleSignIn.swift`.
    "LibrarySync.swift",
    "LibrarySyncEngine.swift",
    "GoogleDrive.swift",
    "GoogleOAuth.swift",
    "GoogleAuthorization.swift",
    "NoriSync.swift",
]

# Gleiche Aufgabe, aber unterschiedlich formuliert. Zurzeit leer – der Eintrag
# bleibt, weil diese Klasse jederzeit wieder entstehen kann.
SHARED_STRUCTURE: list[str] = []

# APIs, die es schlicht nicht gibt. Jede Zeile hier hat einmal einen Build
# gekostet.
NONEXISTENT = {
    r"\.transportBarCustomMenuItems": "transportBarCustomMenuItems ist unter iOS nicht verfügbar; keine tvOS-API im iOS-Player verwenden.",
    r"\\\.openSettings": (
        "EnvironmentValues.openSettings existiert nicht. "
        "Für einen Knopf, der die Einstellungen öffnet: SettingsLink (macOS 14+)."
    ),
    r"NoriTheme\.danger": (
        "NoriTheme hat kein 'danger'. Vorhanden sind bg, surface, elevated, fg, "
        "muted, accent, border — für Fehlertexte .red verwenden. "
        "Ein erfundenes Symbol in einem ViewBuilder meldet der Compiler nicht "
        "als 'has no member', sondern als 'failed to produce diagnostic for "
        "expression' mit Spaltenangabe auf 'some View' — die Meldung sieht "
        "nach einem zu komplexen Ausdruck aus und führt in die Irre."
    ),
}

# Symbole, die neuer sind als das Deployment-Target des jeweiligen Targets.
#
# Der Wert nennt die nötige Version. `#available` hilft hier **nicht**: die
# aufgeführten Symbole sind nicht nur zu neu, sie stehen auch in keinem
# Zweig, den ein Deployment-Target von macOS 14 je erreicht — oder sie
# lassen sich schlicht nicht sinnvoll gaten (Stile, Container).
TOO_NEW_MACOS_14 = {
    r"\.tabViewStyle\(\.sidebarAdaptable\)": "macOS 15",
    r"\.toolbar\(removing:": "macOS 15",
    r"\bTabSection\b": "macOS 15",
    r"\.searchFocused\(": "macOS 15",
    r"\.windowResizability\(\.automatic\)": "macOS 15",
    r"\bGlassEffectContainer\b": "macOS 26",
}

# Symbole, die neuer sind als das Deployment-Target, sich aber hinter
# `#available` sauber verwenden lassen — der Zweig läuft dann nur auf einem
# System, das sie kennt.
#
# Ohne Absicherung bleiben sie ein Fehler: ein ungeschütztes `glassEffect`
# stürzt auf macOS 14 nicht ab, es übersetzt gar nicht erst. Geprüft wird auf
# Dateiebene, weil das Skript keinen Parser hat: liegt im selben Quelltext
# eine passende `#available`-Abfrage, gilt die Verwendung als abgesichert.
GATED_MACOS_14 = {
    r"\.glassEffect\(": (r"#available\(macOS 26", "macOS 26"),
    r"\.scrollEdgeEffectStyle\(": (r"#available\(macOS 26", "macOS 26"),
}

GATED_IOS_17 = {
    r"\.glassEffect\(": (r"#available\(iOS 26", "iOS 26"),
    r"\.scrollEdgeEffectStyle\(": (r"#available\(iOS 26", "iOS 26"),
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

        gated = GATED_MACOS_14 if is_mac else GATED_IOS_17
        floor = "macOS 14.0" if is_mac else "iOS 17.0"
        for pattern, (guard, since) in gated.items():
            if re.search(pattern, src) and not re.search(guard, src):
                add(
                    "ERROR",
                    where,
                    f"Braucht {since}, das Target ist auf {floor} festgelegt, und die "
                    f"Verwendung steht in keinem `{guard.replace(chr(92), '')}…)`-Zweig. "
                    "Über die Hülle in NoriGlass.swift gehen statt direkt.",
                )

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


# APIs, die erst das iOS-18-SDK kennt. `#available(iOS 18.0, *)` schützt nur
# zur Laufzeit — übersetzt wird trotzdem gegen das SDK des Runners.
NEEDS_XCODE_16 = {
    r"\.matchedTransitionSource\s*\(": "matchedTransitionSource",
    r"\.navigationTransition\s*\(\s*\.zoom": "navigationTransition(.zoom:)",
}


def check_fill_in_fixed_frame(folder: Path, label: str) -> None:
    """`scaledToFill()` in einem Stapel mit fester Höhe schneidet Inhalt weg.

    Ein Bild mit `scaledToFill` meldet nach außen eine **größere** Größe, als
    ihm angeboten wurde — das ist der Sinn von „fill". Steht es ohne Klammer in
    einem `ZStack`, wächst der Stapel mit; ein anschließendes
    `.frame(height: N)` zentriert den zu großen Stapel dann in seinem Kasten,
    und `.clipped()` schneidet oben **und unten** ab. Auf der Detailseite war
    dadurch der Abspielknopf zur Hälfte weg.

    In Ordnung und deshalb ohne Meldung:

    - `.frame(maxHeight: .infinity)` vor der festen Höhe — dann nimmt die
      Ansicht das Angebot an und das Bild wird in ihr geschnitten.
    - Das Bild in einer eigenen Ansicht, die per `.background { … }` oder
      `.overlay { … }` dahinter gelegt wird: beide haben keinen Einfluss auf
      die Größe der Hauptansicht, und die feste Höhe steht dann in einer
      anderen Deklaration.

    Geprüft wird je Deklaration, nicht je Datei — sonst schlägt die Regel schon
    an, weil irgendwo in derselben Datei beides einmal vorkommt. Kommentare
    werden vorher entfernt: die Erklärung dieses Fehlers steht im Quelltext und
    nennt naturgemäß beide Bestandteile.
    """
    declaration = re.compile(r"^\s{4}(?:@\w+\s+)*(?:private\s+|static\s+)*(?:var|func)\s+(\w+)")
    fixed_height = re.compile(r"\.frame\(height:\s*\d")

    for path in swift_files(folder):
        lines = strip_comments_and_strings(path.read_text()).splitlines()
        blocks: list[tuple[str, list[str]]] = []
        current: tuple[str, list[str]] | None = None
        for line in lines:
            match = declaration.match(line)
            if match:
                if current:
                    blocks.append(current)
                current = (match.group(1), [line])
            elif current:
                current[1].append(line)
        if current:
            blocks.append(current)

        for name, body in blocks:
            text = "\n".join(body)
            if "scaledToFill" not in text or not fixed_height.search(text):
                continue
            if "maxHeight: .infinity" in text:
                continue
            add(
                "ERROR",
                f"{label}/{path.name}",
                f"'{name}' setzt scaledToFill in einen Stapel mit fester Höhe. Der Stapel "
                "wird dadurch größer als sein Rahmen, wird darin zentriert und verliert "
                "Inhalt an beiden Rändern. Entweder .frame(maxHeight: .infinity) davor, "
                "oder das Bild als .background { … } hinter den Inhalt legen.",
            )


def check_no_secrets() -> None:
    """Kein Schlüssel im Quelltext.

    Der TMDB-Schlüssel stand als Zeichenkette in `AniworldClient.swift`. Ein
    Schlüssel im Quelltext liegt in jedem Klon, in jedem Build und dauerhaft in
    der Git-Historie — wer ihn sperrt, sperrt alle Installationen zugleich.
    Schlüssel gehören in den Schlüsselbund oder in eine Build-Einstellung.

    Gesucht wird nach langen Hex- oder Base64-artigen Zeichenketten und nach
    Zuweisungen an offensichtlich benannte Variablen. Kommentare zählen nicht.
    """
    long_hex = re.compile(r'"[0-9a-f]{32,}"')
    # Eine einzige bewusste Ausnahme: der mitgelieferte TMDB-Schlüssel in
    # `TMDBKeyStore.builtIn`. Der Betreiber hat das für seine private App so
    # entschieden — nachzulesen im Kommentar an der Deklaration. Die Ausnahme
    # ist absichtlich eng an genau diese Zeile geknüpft: jeder andere
    # einkompilierte Schlüssel fällt weiterhin auf, auch ein zweiter in
    # derselben Datei.
    allowed = re.compile(r'private static let builtIn = "[0-9a-f]{32}"')
    named = re.compile(
        r'\b(?:apiKey|api_key|apiSecret|clientSecret|accessToken|refreshToken|password)\b'
        r'\s*(?:=|:)\s*"[^"\n]{8,}"',
        re.IGNORECASE,
    )
    for label, folder in (("iOS", IOS), ("macOS", MAC)):
        for path in swift_files(folder):
            raw = path.read_text()
            # Zeichenketten hier absichtlich stehen lassen — sie sind der Fund.
            without_comments = re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", raw, flags=re.S))
            without_comments = allowed.sub(" ", without_comments)
            for pattern, what in ((long_hex, "lange Hex-Zeichenkette"), (named, "Zuweisung an einen Schlüsselnamen")):
                if pattern.search(without_comments):
                    add(
                        "ERROR",
                        f"{label}/{path.name}",
                        f"Sieht nach einem fest einkompilierten Schlüssel aus ({what}). "
                        "Schlüssel gehören in den Schlüsselbund (siehe TMDBKeyStore) "
                        "oder in eine Build-Einstellung, nicht in den Quelltext.",
                    )
                    break


def check_glass_runner() -> None:
    """Liquid Glass braucht ein SDK ab Xcode 26 — auch mit `#available`.

    `#available` ist eine Laufzeitprüfung. Übersetzt wird trotzdem gegen das
    SDK des Runners, und ein Xcode 16 kennt `glassEffect` überhaupt nicht.
    Der Fehler lautet dann „has no member" und weist auf nichts hin.

    Die Apple-Workflows laufen auf einem self-hosted Mac, dessen Xcode-Version
    diese Datei nicht kennen kann. Deshalb wird geprüft, dass sie
    `tools/require-xcode.sh` mit mindestens 26 aufrufen — das bricht mit
    klarer Meldung ab, statt den Build zwanzig Minuten später scheitern zu
    lassen.
    """
    glass = re.compile(r"\.glassEffect\(|\.scrollEdgeEffectStyle\(")
    used: list[str] = []
    for label, folder in (("iOS", IOS), ("macOS", MAC)):
        for path in swift_files(folder):
            if glass.search(strip_comments_and_strings(path.read_text())):
                used.append(f"{label}/{path.name}")
    if not used:
        return

    where_used = ", ".join(sorted(used))
    for name in ("build-ios.yml", "build-macos.yml"):
        workflow = ROOT / ".github/workflows" / name
        if not workflow.exists():
            continue
        required = re.search(r"tools/require-xcode\.sh\s+(\d+)", workflow.read_text())
        if not required or int(required.group(1)) < 26:
            add(
                "ERROR",
                name,
                f"Die App benutzt Liquid Glass ({where_used}). Das braucht ein SDK "
                "ab Xcode 26; der Workflow fordert weniger an. Schritt auf "
                "`tools/require-xcode.sh 26` setzen.",
            )


def check_ios_runner() -> None:
    """Jeder iOS-Workflow muss zu dem SDK passen, das die App braucht.

    Xcode 15.4 liefert iOS-SDK 17.5 und meldet iOS-18-APIs als „has no member"
    — auch dann, wenn sie sauber hinter `#available` stehen, denn `#available`
    prüft nur zur Laufzeit.

    Bei GitHub-Runnern steht die Xcode-Version über das Label fest, also lässt
    sie sich hier prüfen: `macos-14` reicht nicht. Auf dem self-hosted Mac
    hängt sie dagegen an dem, was dort installiert ist — das kann diese Datei
    nicht wissen. Dafür muss der Workflow selbst einen Schritt haben, der die
    Version liest und mit klarer Meldung abbricht, statt den Build zwanzig
    Minuten später an „has no member" scheitern zu lassen.
    """
    used = set()
    for path in swift_files(IOS):
        src = strip_comments_and_strings(path.read_text())
        for pattern, name in NEEDS_XCODE_16.items():
            if re.search(pattern, src):
                used.add(f"{name} ({path.name})")
    if not used:
        return

    apis = ", ".join(sorted(used))
    for name in ("build-ios.yml",):
        workflow = ROOT / ".github/workflows" / name
        if not workflow.exists():
            continue
        text = workflow.read_text()

        runner = re.search(r"^\s*runs-on:\s*(.+)$", text, re.MULTILINE)
        if not runner:
            continue
        labels = {
            label.strip().strip("'\"").lower()
            for label in runner.group(1).strip().strip("[]").split(",")
        }

        if "self-hosted" in labels:
            # Der Workflow muss `tools/require-xcode.sh` mit mindestens 16
            # aufrufen. Fehlt das, fällt ein zu alter Mac erst im
            # Compilerfehler auf — zwanzig Minuten später und ohne Hinweis
            # darauf, dass es an der Xcode-Version liegt.
            required = re.search(r"tools/require-xcode\.sh\s+(\d+)", text)
            if not required or int(required.group(1)) < 16:
                add(
                    "ERROR",
                    name,
                    "Läuft auf einem self-hosted Runner, dessen Xcode-Version hier "
                    f"nicht feststeht. Die App verwendet iOS-18-APIs: {apis}. Der "
                    "Workflow braucht einen Schritt `tools/require-xcode.sh 16`.",
                )
            continue

        for label in labels:
            match = re.fullmatch(r"macos-(\d+)", label)
            if match and int(match.group(1)) < 15:
                add(
                    "ERROR",
                    name,
                    f"runs-on: {label} bringt Xcode 15 mit iOS-SDK 17. Die App "
                    f"verwendet iOS-18-APIs: {apis}. Mindestens macos-15 nötig.",
                )


def check_ios_package_oauth() -> None:
    """Das verteilbare iOS-Paket muss Google-Abgleich haben.

    Nori 1.25.0 (37) ging als IPA mit leerer `GoogleClientID` hinaus: der
    Workflow stellte `Google.local.xcconfig` nicht bereit, und weil eine fehlende
    Konfiguration für Entwicklungs-Builds erlaubt ist, blieb der Lauf grün.

    Geprüft wird, dass der Job `ipa` in `Build iOS` die Konfiguration vor dem
    Build mit `tools/configure-google-oauth.py --ios` schreibt, das gebaute
    Programm und die fertige IPA vor dem Hochladen prüft und nirgends ein
    Client-Secret anfasst — und dass die iOS-`Info.plist` die Client-ID
    weiterhin aus der Build-Einstellung bezieht und kein Secret kennt.

    Bis 2.6.0 stand das in einem eigenen Workflow `Package iOS IPA`; seitdem
    ist es ein Job neben dem Simulator-Build, und nur dieser Job zählt — der
    Simulator-Build lädt bei einem Fehlschlag sein eigenes Protokoll hoch.
    """
    name = "build-ios.yml"
    workflow = ROOT / ".github/workflows" / name
    if not workflow.exists():
        return
    whole = workflow.read_text()
    job = re.search(r"^  ipa:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)", whole, re.MULTILINE | re.DOTALL)
    if job is None:
        add("ERROR", name, "Der Job `ipa` fehlt — ohne ihn gibt es keine geprüfte IPA.")
        return
    text = job.group(1)

    def position(pattern: str) -> int:
        match = re.search(pattern, text)
        return match.start() if match else -1

    configure = position(r"tools/configure-google-oauth\.py\s+--ios\b")
    build = position(r"-sdk\s+iphoneos")
    verify_app = position(r"tools/configure-google-oauth\.py\s+--verify-ios-app\b")
    verify_ipa = position(r"tools/configure-google-oauth\.py\s+--verify-ios-ipa\b")
    upload = position(r"actions/upload-artifact@")

    if configure < 0 or build < 0 or configure > build:
        add("ERROR", name, "Vor dem Geräte-Build fehlt `python3 tools/configure-google-oauth.py --ios`. "
            "Ohne ihn entsteht eine IPA ohne Google-Abgleich (so geschehen bei 1.25.0).")
    if verify_app < 0 or verify_app < build:
        add("ERROR", name, "Nach dem Build fehlt `tools/configure-google-oauth.py --verify-ios-app` "
            "für das gebaute Nori.app.")
    if verify_ipa < 0 or upload < 0 or verify_ipa > upload:
        add("ERROR", name, "Vor dem Hochladen fehlt `tools/configure-google-oauth.py --verify-ios-ipa` "
            "für die fertige IPA.")
    if re.search(r"GOOGLE_CLIENT_SECRET|--macos\b|--webos\b", whole):
        add("ERROR", name, "Der iOS-Paketlauf fasst eine fremde Google-Konfiguration an. "
            "iOS bekommt nur seine Client-ID, nie ein Secret.")

    plist = (IOS / "Info.plist").read_text() if (IOS / "Info.plist").exists() else ""
    if "<key>GoogleClientID</key>" not in plist or "$(GOOGLE_CLIENT_ID)" not in plist:
        add("ERROR", "iOS/Info.plist", "GoogleClientID muss aus der Build-Einstellung $(GOOGLE_CLIENT_ID) kommen.")
    if "GoogleClientSecret" in plist:
        add("ERROR", "iOS/Info.plist", "GoogleClientSecret gehört nicht in die iOS-App.")
    xcconfig = ROOT / "native/Nori-iOS/Config/Nori.xcconfig"
    if xcconfig.exists() and '#include? "Google.local.xcconfig"' not in xcconfig.read_text():
        add("ERROR", "native/Nori-iOS/Config/Nori.xcconfig",
            '`#include? "Google.local.xcconfig"` fehlt — dort schreibt das Werkzeug die Client-ID hin.')


def check_main_actor_calls(folder: Path, label: str) -> None:
    """`@MainActor`-Methoden dürfen nicht synchron aus einer View-Hilfe kommen.

    `var body` ist über die View-Konformanz an den Main-Actor gebunden, eine
    ausgelagerte `private var chrome: some View` aber nicht. Ein direkter
    Aufruf dort meldet der Compiler als „call to main actor-isolated instance
    method '…' in a synchronous nonisolated context" — im iOS-Build zweimal
    passiert. Die im Projekt verwendete Bauform ist
    `Task { @MainActor in methode() }`.

    Erkannt wird bewusst grob: ein Aufruf einer bekannten `@MainActor`-Methode
    in einer View-Hilfe, außerhalb jedes `Task {`-Blocks und ohne `await`.

    Der Block wird über die Klammertiefe verfolgt, nicht über die Zeile. Ein
    `Task { @MainActor in` über mehrere Zeilen — die übliche Bauform in den
    Rückrufen des Players — galt vorher als Fehler, obwohl genau das die
    empfohlene Lösung ist.
    """
    for path in swift_files(folder):
        lines = path.read_text().splitlines()

        isolated = set()
        for index, line in enumerate(lines[:-1]):
            if line.strip() == "@MainActor":
                match = re.search(r"\bfunc\s+(\w+)", lines[index + 1])
                if match:
                    isolated.add(match.group(1))
        if not isolated:
            continue

        # Grenzen der View-Hilfen: alles zwischen einer `some View`-Deklaration
        # (außer `var body`) und der nächsten Deklaration auf gleicher Ebene.
        declaration = re.compile(r"^\s{4}(?:@\w+\s+)*(?:private\s+)?(var|func)\s+(\w+)")
        current: str | None = None
        # Klammertiefe, ab der wir uns in einem `Task { … }` befinden. Leer
        # heißt: außerhalb.
        task_depths: list[int] = []
        depth = 0
        for index, line in enumerate(lines):
            match = declaration.match(line)
            if match:
                is_view_helper = "some View" in line and match.group(2) != "body"
                current = match.group(2) if is_view_helper else None
                task_depths = []
                depth = 0
                continue

            opens_task = "Task {" in line or "Task{" in line
            in_task = bool(task_depths)
            if current is not None and not in_task and not opens_task and "await" not in line:
                for name in isolated:
                    if re.search(rf"(?<![\w.]){re.escape(name)}\s*\(", line):
                        add(
                            "ERROR",
                            f"{label}/{path.name}:{index + 1}",
                            f"{name}() ist @MainActor, wird aber synchron aus '{current}' "
                            f"aufgerufen. Stattdessen: Task {{ @MainActor in {name}(…) }}.",
                        )

            # Klammern der Zeile verrechnen; ein `Task {` merkt sich die Tiefe,
            # auf der sein Block endet.
            for char in line:
                if char == "{":
                    depth += 1
                    if opens_task and not task_depths:
                        task_depths.append(depth)
                        opens_task = False
                elif char == "}":
                    if task_depths and depth == task_depths[-1]:
                        task_depths.pop()
                    depth -= 1
            continue


def png_info(path: Path) -> tuple[int, int, bool] | None:
    """Breite, Höhe und ob ein Alphakanal vorhanden ist — ohne Fremdbibliothek.

    Die Angaben stehen im IHDR direkt hinter der PNG-Signatur.
    """
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 26:
        return None
    width, height = struct.unpack(">II", data[16:24])
    color_type = data[25]
    return width, height, color_type in (4, 6)


def check_app_icons() -> None:
    """Deklarierte und tatsächliche Icon-Größe müssen übereinstimmen.

    Ein 256×256-Bild, das als 1024×1024 eingetragen war, hat den iOS-Build mit
    „app icon set named 'AppIcon' did not have any applicable content" scheitern
    lassen — eine Meldung, die die Ursache nicht nennt. iOS-Icons dürfen
    außerdem keinen Alphakanal haben.
    """
    for label, folder in (("iOS", IOS), ("macOS", MAC)):
        iconset = folder / "Assets.xcassets/AppIcon.appiconset"
        contents = iconset / "Contents.json"
        if not contents.exists():
            continue
        try:
            entries = json.loads(contents.read_text()).get("images", [])
        except json.JSONDecodeError as error:
            add("ERROR", f"{label}/AppIcon", f"Contents.json ist kein gültiges JSON: {error}")
            continue

        for entry in entries:
            filename = entry.get("filename")
            if not filename:
                continue
            image = iconset / filename
            if not image.exists():
                add("ERROR", f"{label}/AppIcon", f"{filename} ist eingetragen, fehlt aber.")
                continue
            info = png_info(image)
            if info is None:
                add("ERROR", f"{label}/AppIcon", f"{filename} ist keine lesbare PNG-Datei.")
                continue
            width, height, has_alpha = info

            size = entry.get("size", "")
            scale = int(str(entry.get("scale", "1x")).rstrip("x") or 1)
            if "x" in size:
                try:
                    base = float(size.split("x")[0])
                except ValueError:
                    continue
                expected = int(base * scale)
                if (width, height) != (expected, expected):
                    add(
                        "ERROR",
                        f"{label}/AppIcon",
                        f"{filename} ist {width}×{height}, eingetragen als "
                        f"{size} @{scale}x, also {expected}×{expected}.",
                    )

            if label == "iOS" and has_alpha:
                add(
                    "ERROR",
                    f"{label}/AppIcon",
                    f"{filename} hat einen Alphakanal. iOS-App-Icons müssen deckend sein.",
                )


def check_icon_declared() -> None:
    """Eine handgepflegte Info.plist muss ihren Iconsatz selbst nennen.

    `CFBundleIconName` verweist auf den Iconsatz im Assetkatalog. Xcode trägt
    den Schlüssel nur bei `GENERATE_INFOPLIST_FILE = YES` nach — beide Targets
    stehen hier auf `NO`. Fehlt er, findet iOS kein Icon: die installierte App
    bleibt als Platzhalterkachel auf dem Home-Bildschirm stehen und sieht aus,
    als lade sie endlos. Auf macOS zeigen Dock und Finder das graue
    Standardsymbol.
    """
    targets = [
        ("iOS", IOS, ROOT / "native/Nori-iOS/Nori.xcodeproj/project.pbxproj"),
        ("macOS", MAC, ROOT / "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj"),
    ]
    for label, folder, pbx in targets:
        plist = folder / "Info.plist"
        iconset = folder / "Assets.xcassets/AppIcon.appiconset"
        if not plist.exists() or not iconset.is_dir() or not pbx.exists():
            continue

        # Bei generierter Info.plist erledigt Xcode das selbst.
        generated = set(re.findall(r"GENERATE_INFOPLIST_FILE\s*=\s*(\w+)", pbx.read_text()))
        if generated and generated != {"NO"}:
            continue

        text = plist.read_text()
        if "CFBundleIconName" in text:
            continue
        add(
            "ERROR",
            f"{label}/Info.plist",
            "CFBundleIconName fehlt, obwohl GENERATE_INFOPLIST_FILE auf NO steht "
            "und ein AppIcon.appiconset vorliegt. Ohne den Schlüssel bleibt das "
            "Icon leer — auf iOS hängt die App als Platzhalter auf dem "
            "Home-Bildschirm.",
        )


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


def check_pbxproj_identifiers() -> None:
    """Keine Kennung zweimal, und keine Quelldatei ohne Build-Eintrag.

    Die Xcode-Projekte vergeben kurze Kennungen von Hand (`AB07`, `AC42`)
    statt der üblichen 24-stelligen Hex-Kennungen. Das ist lesbar, hat aber
    eine Falle: zwei Zweige, die gleichzeitig Dateien hinzufügen, leiten ihre
    freien Nummern von **derselben** Basis ab und vergeben dieselben.

    Git merkt davon nichts — die Zeilen stehen an verschiedenen Stellen und
    lassen sich konfliktfrei zusammenführen. Xcode löst eine doppelte Kennung
    dann auf genau eine Datei auf, und die andere wird stillschweigend nicht
    mehr übersetzt. Im Build sieht das aus wie ein fehlender Typ irgendwo
    ganz woanders: „cannot find 'CatalogService' in scope", während die Datei
    unverändert im Ordner liegt.

    Genau so ist der Lauf `Build iOS` einmal rot geworden, nachdem der
    Katalog-Umbau und der Kalender-Umbau kurz nacheinander gelandet waren.
    """
    projects = [
        ("iOS", ROOT / "native/Nori-iOS/Nori.xcodeproj/project.pbxproj"),
        ("macOS", ROOT / "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj"),
    ]
    reference = re.compile(r"^\t\t(A[BC]\d+) /\* (.+?) \*/ = \{isa = PBX(BuildFile|FileReference)", re.M)

    for label, path in projects:
        if not path.is_file():
            continue
        src = path.read_text()

        owners: dict[str, set[str]] = {}
        for identifier, name, _ in reference.findall(src):
            # „Foo.swift in Sources" und „Foo.swift" gehören derselben Datei.
            owners.setdefault(identifier, set()).add(name.removesuffix(" in Sources"))

        for identifier, names in sorted(owners.items()):
            if len(names) > 1:
                add(
                    "ERROR",
                    f"{label}/project.pbxproj",
                    f"Kennung {identifier} ist an mehrere Dateien vergeben: "
                    f"{', '.join(sorted(names))}. Xcode übersetzt dann nur eine davon. "
                    "Eine der beiden auf eine freie Nummer umschreiben.",
                )

        # Eine Datei, die referenziert, aber nicht gebaut wird, fehlt im
        # Ergebnis genauso — nur ohne doppelte Kennung als Hinweis.
        referenced = {
            name
            for identifier, name, kind in reference.findall(src)
            if kind == "FileReference" and name.endswith(".swift")
        }
        built = {
            name.removesuffix(" in Sources")
            for identifier, name, kind in reference.findall(src)
            if kind == "BuildFile"
        }
        for name in sorted(referenced - built):
            add(
                "ERROR",
                f"{label}/project.pbxproj",
                f"{name} ist als Datei eingetragen, steht aber in keiner Sources-Phase "
                "und wird deshalb nicht übersetzt.",
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
    check_main_actor_calls(IOS, "iOS")
    check_main_actor_calls(MAC, "macOS")
    check_ios_runner()
    check_glass_runner()
    check_ios_package_oauth()
    check_fill_in_fixed_frame(IOS, "iOS")
    check_fill_in_fixed_frame(MAC, "macOS")
    check_no_secrets()
    check_app_icons()
    check_icon_declared()
    check_deployment_targets()
    check_pbxproj_identifiers()

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

