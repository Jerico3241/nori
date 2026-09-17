#!/usr/bin/env python3
"""Nori-Releases: eine Version, ein Tag, ein GitHub Release, alle Plattformen.

Aufgerufen vom Workflow **Nori Release** (`.github/workflows/release.yml`) und
von den Plattform-Läufen, die er aufruft — `Build iOS`, `Build macOS`,
`Build webOS` und `Build Windows`.

    python3 tools/nori-release.py meta           --platform ios [--release-version 2.6.0]
    python3 tools/nori-release.py prepare        --version v2.6.0 --platforms ios,macos,webos,windows
    python3 tools/nori-release.py source-package --output Nori-macOS-Source-v2.6.0.zip
    python3 tools/nori-release.py check-app      --platform macos --app <Nori.app>
    python3 tools/nori-release.py verify         --asset webos --file <Paket> [--release-version 2.6.0]
    python3 tools/nori-release.py notes          [--platforms ios,macos,webos,windows]
    python3 tools/nori-release.py publish        --version 2.6.0 --platforms … --dir <Ordner> --sha256 ios=<…> … --commit <SHA>
    python3 tools/nori-release.py validate       --version 2.6.0 --platforms … --commit <SHA>
    python3 tools/nori-release.py cleanup        --version 2.6.0 --platforms … --commit <SHA> --keep-run <ID>

Die Regeln stehen hier und nirgends sonst:

* Ein Release heißt `Nori v<VERSION>`, sein Tag `v<VERSION>`. Die Version kommt
  aus den Projektdateien des geprüften Commits (`tools/nori-version.py`) und
  muss dort an jeder Stelle gleich sein; die Eingabe im Workflow bestätigt sie
  nur. Getrennte Plattform-Tags wie `ios-v…` entstehen nicht mehr.
* Jede Version bekommt genau einen Release. Gibt es Tag, Release oder Entwurf
  schon, oder trägt ein vorhandener Tag — auch ein alter `ios-v…` — eine
  gleiche oder höhere Version, bricht der Lauf ab. Verschoben, überschrieben
  oder gelöscht wird dabei nie etwas. Die Buildnummern von iOS und macOS
  müssen über denen jedes früheren Release-Tags liegen.
* Angehängt werden genau die Pakete der gewählten Plattformen, benannt
  `Nori-<Plattform>-v<VERSION>.<Endung>`, und `checksums-sha256.txt`. Jedes
  Paket wird am Namen, an der Prüfsumme aus seinem Paket-Job und am Inhalt
  erkannt — Version, Build, keine Zugangsdaten außer den vorgesehenen.
* Die Release Notes kommen aus dem Abschnitt `[Nori <VERSION>]` in
  `CHANGELOG.md`, ohne interne OAuth-, Secret- und Runner-Einzelheiten.
* Aufgeräumt wird erst, wenn der Release veröffentlicht und nachgeprüft ist,
  und nur bei Läufen der Nori-Build- und Release-Workflows
  (`CLEANUP_WORKFLOWS`) — nie der laufende, nie ein unfertiger. Releases,
  Anhänge, Tags und Branches kann dieses Werkzeug gar nicht löschen: `GitHub`
  lässt `DELETE` nur für Workflow-Läufe und -Artefakte zu.

Die GitHub-API wird über `urllib` angesprochen, nicht über die `gh`-CLI: der
Runner kommt ohne Homebrew aus (docs/self-hosted-runner.md). Das Token kommt aus
`GITHUB_TOKEN` oder `GH_TOKEN` und erscheint in keiner Ausgabe.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import http.client
import importlib.util
import io
import json
import os
import plistlib
import re
import ssl
import stat
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

ROOT = Path(__file__).resolve().parent.parent
TOOLS = Path(__file__).resolve().parent
SECRETS_DIR = Path.home() / ".config/nori/secrets"

SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")

CHECKSUMS = "checksums-sha256.txt"
RELEASE_RETENTION_DAYS = 1   # Übergabe vom Paket-Job an den Release-Job desselben Laufs
TEST_RETENTION_DAYS = 3      # Testpakete und Diagnose aus gewöhnlichen Läufen


class ReleaseError(Exception):
    """Ein Grund, keinen Release anzulegen. Die Meldung ist fürs Protokoll gedacht."""


class GitHubError(ReleaseError):
    def __init__(self, status: int, message: str, rate_limited: bool = False) -> None:
        super().__init__(message)
        self.status = status
        self.rate_limited = rate_limited


def load_tool(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, TOOLS / filename)
    module = importlib.util.module_from_spec(spec)
    # Dataclasses schlagen ihr Modul in sys.modules nach.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


_VERSION_TOOL = None


def version_tool():
    """tools/nori-version.py — die Liste der Stellen, an denen die Nummer steht."""
    global _VERSION_TOOL
    if _VERSION_TOOL is None:
        _VERSION_TOOL = load_tool("nori_version", "nori-version.py")
    _VERSION_TOOL.ROOT = ROOT
    return _VERSION_TOOL


def version_key(version: str) -> tuple[int, int, int]:
    major, minor, patch = (int(part) for part in version.split("."))
    return major, minor, patch


def normalize_version(value: str | None) -> str:
    tool = version_tool()
    try:
        return tool.normalize_version(value)
    except tool.VersionError as error:
        raise ReleaseError(str(error)) from None


# ── Plattformen und Pakete ───────────────────────────────────────────────────


@dataclass(frozen=True)
class AssetSpec:
    key: str
    platform: str
    template: str         # Dateiname; {suffix} ist nur bei Testpaketen belegt
    kind: str             # bestimmt die Prüfung
    content_type: str
    label: str
    hint: str

    def name(self, version: str, suffix: str = "") -> str:
        return self.template.format(version=version, suffix=suffix)


@dataclass(frozen=True)
class Platform:
    key: str
    display: str          # in den Release Notes
    short: str            # im Dateinamen: Nori-<short>-v…
    workflow: str
    assets: tuple[str, ...]
    legacy_prefix: str    # Tag-Schema vor 2.6.0


ASSETS = {
    "ios": AssetSpec(
        "ios", "ios", "Nori-iOS-v{version}{suffix}.ipa", "ipa", "application/octet-stream", "iOS / iPadOS",
        "Unsigniert – vor der Installation signieren, etwa mit Feather, ESign oder SideStore.",
    ),
    "macos": AssetSpec(
        "macos", "macos", "Nori-macOS-Source-v{version}{suffix}.zip", "source-zip", "application/zip", "macOS",
        "Quellpaket – in Xcode öffnen und mit einem eigenen Team signieren; ein fertiges Programm liegt nicht bei.",
    ),
    "webos": AssetSpec(
        "webos", "webos", "Nori-webOS-v{version}{suffix}.ipk", "ipk", "application/octet-stream", "LG webOS",
        "Installationspaket für LG-Fernseher im Entwicklermodus.",
    ),
    "windows-installer": AssetSpec(
        "windows-installer", "windows", "Nori-Windows-v{version}{suffix}.exe", "windows-installer",
        "application/vnd.microsoft.portable-executable", "Windows",
        "Installer ohne Administratorrechte. Nicht signiert: SmartScreen fragt beim ersten Start nach "
        "(„Weitere Informationen“ → „Trotzdem ausführen“).",
    ),
    "windows-portable": AssetSpec(
        "windows-portable", "windows", "Nori-Windows-v{version}{suffix}.zip", "windows-portable", "application/zip",
        "Windows (ohne Installation)", "Entpacken und `Nori.exe` starten – es wird nichts installiert.",
    ),
}

PLATFORMS = {
    "ios": Platform("ios", "iOS / iPadOS", "iOS", ".github/workflows/build-ios.yml", ("ios",), "ios-v"),
    "macos": Platform("macos", "macOS", "macOS", ".github/workflows/build-macos.yml", ("macos",), "macos-v"),
    "webos": Platform("webos", "LG webOS", "webOS", ".github/workflows/build-webos.yml", ("webos",), "webos-v"),
    "windows": Platform("windows", "Windows", "Windows", ".github/workflows/build-windows.yml",
                        ("windows-installer", "windows-portable"), "windows-v"),
}

# Plattformen ohne App in diesem Repository. Sie stehen in den Notes unter
# „nicht enthalten“ — ein Paket für sie gibt es nicht, und es wird keines erfunden.
NOT_AVAILABLE = {
    "Android": "keine App in diesem Repository",
    "Google TV": "keine App in diesem Repository",
}

# Längere Präfixe zuerst: `webos-v2.2.1` ist kein `v…`-Tag.
TAG_PREFIXES = tuple(sorted({"v", *(platform.legacy_prefix for platform in PLATFORMS.values())}, key=len, reverse=True))

XCODE_PROJECTS = {
    "ios": "native/Nori-iOS/Nori.xcodeproj/project.pbxproj",
    "macos": "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj",
}
WEBOS_APPINFO = "apps/webos/appinfo.json"

# Inhalt des macOS-Quellpakets: diese Pfade, genau so, wie sie im Commit stehen.
SOURCE_PATHS = {
    "macos": (
        "native/Nori-macOS",
        "native/NoriCore",
        "native/Package.swift",
        "native/Tests",
        "config/contract.json",
        "README.md",
        "CHANGELOG.md",
    ),
}

# Welche echten Werte vom Rechner ein Paket tragen darf. Alles andere aus
# ~/.config/nori/secrets ist in jedem Paket ein Fehler.
ALLOWED_CREDENTIALS = {
    "ipa": {"google-ios-client-id"},
    "ipk": {"google-webos-oauth.json client_id", "google-webos-oauth.json client_secret"},
    "source-zip": set(),
    "windows-installer": set(),
    "windows-portable": set(),
}
# Der Desktop-Client von Windows kommt als Umgebungsvariable in den Build; er
# darf im Windows-Paket stehen und sonst nirgends.
DESKTOP_CLIENT_ENV = ("NORI_GOOGLE_DESKTOP_CLIENT_ID", "NORI_GOOGLE_DESKTOP_CLIENT_SECRET")


def platform_for(key: str) -> Platform:
    try:
        return PLATFORMS[key]
    except KeyError:
        raise ReleaseError(f"Unbekannte Plattform {key!r} – erwartet {', '.join(PLATFORMS)}") from None


def asset_for(key: str) -> AssetSpec:
    try:
        return ASSETS[key]
    except KeyError:
        raise ReleaseError(f"Unbekanntes Paket {key!r} – erwartet {', '.join(ASSETS)}") from None


def parse_platforms(value: str | Iterable[str]) -> list[str]:
    """`ios,webos` → in fester Reihenfolge, ohne Doppelte; leer oder unbekannt ist ein Fehler."""
    items = value.split(",") if isinstance(value, str) else list(value)
    wanted = {item.strip().lower() for item in items if item and item.strip()}
    unknown = sorted(wanted - set(PLATFORMS))
    if unknown:
        raise ReleaseError(f"Unbekannte Plattform {', '.join(unknown)} – erwartet {', '.join(PLATFORMS)}")
    if not wanted:
        raise ReleaseError("Keine Plattform gewählt – ein Release ohne Pakete gibt es nicht")
    return [key for key in PLATFORMS if key in wanted]


def expected_assets(version: str, platforms: Iterable[str]) -> dict[str, AssetSpec]:
    return {ASSETS[key].name(version): ASSETS[key] for platform in platforms for key in PLATFORMS[platform].assets}


def tag_version(name: str) -> str | None:
    for prefix in TAG_PREFIXES:
        if name.startswith(prefix) and SEMVER.match(name[len(prefix):]):
            return name[len(prefix):]
    return None


# ── Version aus dem Commit ───────────────────────────────────────────────────


@dataclass(frozen=True)
class Meta:
    version: str
    commit: str
    builds: dict
    bundle_ids: dict

    @property
    def tag(self) -> str:
        return f"v{self.version}"

    @property
    def title(self) -> str:
        return f"Nori v{self.version}"


def run_git(*args: str, binary: bool = False, stdin: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, input=stdin, text=not binary)


def git(*args: str) -> str:
    result = run_git(*args)
    if result.returncode != 0:
        raise ReleaseError(f"git {args[0]} fehlgeschlagen: {result.stderr.strip()[:300]}")
    return result.stdout


def resolve_commit(ref: str) -> str:
    result = run_git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    sha = result.stdout.strip()
    if result.returncode != 0 or not COMMIT.match(sha):
        raise ReleaseError(f"Commit {ref!r} ist nicht vorhanden")
    return sha


def file_at(commit: str, path: str) -> str:
    return git("show", f"{commit}:{path}")


def read_meta(ref: str = "HEAD", expected: str | None = None) -> Meta:
    """Gemeinsame Version, Buildnummern und Kennungen so, wie sie im Commit stehen."""
    commit = resolve_commit(ref)
    tool = version_tool()
    try:
        state = tool.read_state(commit)
        version = state.version
    except tool.VersionError as error:
        raise ReleaseError(str(error)) from None
    if expected is not None:
        wanted = normalize_version(expected)
        if wanted != version:
            raise ReleaseError(
                f"Verlangt ist Version {wanted}, Commit {commit[:7]} trägt {version} – "
                "erst die Nummer im Repository setzen (python3 tools/nori-version.py set …), dann releasen"
            )
    try:
        appinfo = json.loads(file_at(commit, WEBOS_APPINFO))
    except json.JSONDecodeError:
        raise ReleaseError(f"{WEBOS_APPINFO} ist kein gültiges JSON") from None
    bundle_ids = {**state.bundle_ids, "webos": str(appinfo.get("id", ""))}
    return Meta(version, commit, dict(state.builds), bundle_ids)


def check_documents(meta: Meta) -> None:
    tool = version_tool()
    try:
        tool.check(meta.version, meta.commit, documents=True)
    except tool.VersionError as error:
        raise ReleaseError(str(error)) from None


def build_at_tag(tag: str, platform: str) -> str | None:
    """Buildnummer eines Apple-Projekts im Stand eines Tags — None, wenn es dort keins gab."""
    if run_git("rev-parse", "--verify", "--quiet", f"refs/tags/{tag}").returncode != 0:
        fetched = run_git("fetch", "--quiet", "--no-tags", "origin", f"refs/tags/{tag}:refs/tags/{tag}")
        if fetched.returncode != 0:
            raise ReleaseError(f"Tag {tag} ist lokal nicht vorhanden und nicht abrufbar – fehlt `fetch-depth: 0`?")
    shown = run_git("show", f"refs/tags/{tag}:{XCODE_PROJECTS[platform]}")
    if shown.returncode != 0:
        return None
    values = set(version_tool().settings(shown.stdout, "CURRENT_PROJECT_VERSION"))
    numbers = [int(value) for value in values if value.isdigit()]
    return str(max(numbers)) if numbers else None


def check_builds(meta: Meta, tags: Iterable[str]) -> None:
    """iOS und macOS müssen als neuer erkannt werden — auch gegenüber alten Plattform-Tags."""
    for platform, build in meta.builds.items():
        prefixes = ("v", PLATFORMS[platform].legacy_prefix)
        for tag in sorted(tags):
            if not any(tag.startswith(prefix) and SEMVER.match(tag[len(prefix):]) for prefix in prefixes):
                continue
            earlier = build_at_tag(tag, platform)
            if earlier is not None and int(build) <= int(earlier):
                raise ReleaseError(
                    f"Buildnummer {platform} {build} ist nicht größer als {earlier} in {tag} – das System erkennt "
                    "den Stand sonst nicht als neuer. `python3 tools/nori-version.py set …` erhöht sie."
                )


# ── Pakete prüfen ────────────────────────────────────────────────────────────

CLIENT_ID_ANY = re.compile((r"\d{6,}-[a-z0-9]{20,}" + re.escape(".apps.googleusercontent.com")).encode())
CLIENT_SECRET_ANY = re.compile(("GOCSPX" + r"-[A-Za-z0-9_-]{10,}").encode())
# Werte, nicht Namen: der Hoster-Code nennt Cookies beim Namen, das ist erlaubt.
TOKEN_PATTERNS = (
    (re.compile(("ya" + r"29\.[A-Za-z0-9_-]{20,}").encode()), "Access-Token"),
    (re.compile(("1/" + r"/0[A-Za-z0-9_-]{20,}").encode()), "Refresh-Token"),
    (re.compile(rb'"(?:access_token|refresh_token|id_token|device_code|user_code)"\s*:\s*"[^"\s]{8,}"'),
     "Token oder Gerätecode"),
    (re.compile(rb"(?:Set-Cookie:\s*[^\s=;]+=[^\s;]{16,}|cf_clearance=[A-Za-z0-9_.-]{20,}"
                rb"|__Secure-[0-9A-Za-z]*PSID=[A-Za-z0-9_.-]{20,})"), "Cookie"),
    (re.compile(("-----BEGIN [A-Z ]*PRIV" + "ATE KEY-----").encode()), "privater Schlüssel"),
)
FORBIDDEN_FILES = re.compile(
    r"(^|/)(\.env(\.[^/]*)?|[^/]*\.local\.xcconfig|client_secret[^/]*\.json|[^/]*oauth[^/]*\.json"
    r"|google-services\.json|GoogleService-Info\.plist|Cookies|\.netrc"
    r"|[^/]*\.(log|har|trace|mobileprovision|p12|pem|binarycookies))$"
    r"|(^|/)(test-shots|test-results|playwright-report|DerivedData)/",
    re.IGNORECASE,
)

VERIFIERS = {
    "ipa": "verify_ipa",
    "ipk": "verify_ipk",
    "source-zip": "verify_source_zip",
    "windows-installer": "verify_windows_installer",
    "windows-portable": "verify_windows_portable",
}


def known_credentials() -> dict[str, str]:
    """Echte Werte dieses Rechners, um sie wiederzuerkennen. Werden nie ausgegeben."""
    values: dict[str, str] = {}
    if not SECRETS_DIR.is_dir():
        return values
    for path in sorted(SECRETS_DIR.glob("*.json")):
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(document, dict):
            continue
        for section in document.values():
            if not isinstance(section, dict):
                continue
            for field in ("client_id", "client_secret"):
                value = section.get(field)
                if isinstance(value, str) and len(value) >= 16:
                    values[f"{path.name} {field}"] = value
    ios = SECRETS_DIR / "google-ios-client-id"
    if ios.is_file():
        value = ios.read_text(encoding="utf-8").strip()
        if len(value) >= 16:
            values["google-ios-client-id"] = value
    return values


def desktop_credentials() -> dict[str, str]:
    """Der Desktop-Client aus der Umgebung des Windows-Builds. Werte werden nie ausgegeben."""
    return {name: os.environ.get(name, "").strip() for name in DESKTOP_CLIENT_ENV if os.environ.get(name, "").strip()}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_sha256(value: str | None) -> str:
    text = (value or "").strip().lower().removeprefix("sha256:")
    if not SHA256.match(text):
        raise ReleaseError("Prüfsumme des geprüften Pakets fehlt oder ist ungültig")
    return text


def verify_asset(meta: Meta, spec: AssetSpec, path: Path, expected_sha256: str | None = None, suffix: str = "") -> str:
    """Name, Prüfsumme und Inhalt des Pakets gegen die Version des Commits."""
    if path.is_symlink() or not path.is_file():
        raise ReleaseError(f"{path.name} ist keine reguläre Datei")
    wanted = spec.name(meta.version, suffix)
    if path.name != wanted:
        raise ReleaseError(f"Falsches Paket: {path.name} – für {meta.tag} erwartet {wanted}")
    digest = sha256_file(path)
    if expected_sha256 is not None:
        expected = normalize_sha256(expected_sha256)
        if digest != expected:
            raise ReleaseError(
                f"{path.name}: Prüfsumme {digest[:12]}… weicht vom geprüften Paket ab ({expected[:12]}…)"
            )
    globals()[VERIFIERS[spec.kind]](meta, path)
    return digest


def safe_member(name: str, label: str) -> None:
    if name.startswith("/") or "\\" in name or ".." in name.split("/"):
        raise ReleaseError(f"{label}: unzulässiger Pfad im Archiv: {name}")


def check_names(label: str, names: Iterable[str]) -> None:
    for name in names:
        if FORBIDDEN_FILES.search(name):
            raise ReleaseError(f"{label}: unzulässige Datei im Paket: {name}")


def expect_equal(label: str, what: str, actual: object, expected: str | None) -> None:
    if actual is None or str(actual) != str(expected):
        raise ReleaseError(f"{label}: {what} ist {actual!r}, der Release verlangt {expected!r}")


def scan_contents(label: str, files: Iterable[tuple[str, bytes]], kind: str, patterns: bool,
                  allowed_values: Iterable[str] = (), secret_pattern_allowed: bool = False) -> None:
    """Keine Tokens, Cookies oder fremden Zugangsdaten im Inhalt."""
    allowed = ALLOWED_CREDENTIALS[kind]
    permitted = set(allowed_values)
    known = {origin: value.encode() for origin, value in known_credentials().items()
             if origin not in allowed and value not in permitted}
    for name, data in files:
        if patterns:
            for pattern, what in TOKEN_PATTERNS:
                if pattern.search(data):
                    raise ReleaseError(f"{label}: {what} in {name}")
            if not secret_pattern_allowed and CLIENT_SECRET_ANY.search(data):
                raise ReleaseError(f"{label}: Google-Client-Secret in {name}")
        for origin, value in known.items():
            if value in data:
                raise ReleaseError(f"{label}: Zugangsdaten aus {origin} in {name}")


def open_zip(path: Path, label: str) -> zipfile.ZipFile:
    try:
        return zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        raise ReleaseError(f"{label}: kein gültiges ZIP-Archiv") from None


def verify_ipa(meta: Meta, path: Path) -> None:
    label = path.name
    with open_zip(path, label) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        for name in names:
            safe_member(name, label)
        outside = [name for name in names if not name.startswith("Payload/")]
        if outside:
            raise ReleaseError(f"{label}: Dateien außerhalb von Payload/: {', '.join(outside[:3])}")
        apps = {name.split("/")[1] for name in names if name.count("/") >= 2}
        if apps != {"Nori.app"}:
            raise ReleaseError(f"{label}: erwartet genau Payload/Nori.app, gefunden {', '.join(sorted(apps)) or 'nichts'}")
        check_names(label, names)
        try:
            info = plistlib.loads(archive.read("Payload/Nori.app/Info.plist"))
        except KeyError:
            raise ReleaseError(f"{label}: Payload/Nori.app/Info.plist fehlt") from None
        except Exception as error:  # plistlib wirft je nach Format verschiedene Fehler
            raise ReleaseError(f"{label}: Info.plist nicht lesbar ({type(error).__name__})") from None
        expect_equal(label, "Version (CFBundleShortVersionString)", info.get("CFBundleShortVersionString"), meta.version)
        expect_equal(label, "Build (CFBundleVersion)", info.get("CFBundleVersion"), meta.builds["ios"])
        expect_equal(label, "Bundle-ID", info.get("CFBundleIdentifier"), meta.bundle_ids["ios"])
        files = ((entry.filename, archive.read(entry)) for entry in infos if not entry.is_dir())
        scan_contents(label, files, "ipa", patterns=True)


def webos_checker():
    return load_tool("check_webos_package", "check-webos-package.py")


def verify_ipk(meta: Meta, path: Path) -> None:
    label = path.name
    result = webos_checker().read_ipk(path)
    if isinstance(result, str):
        raise ReleaseError(f"{label}: {result}")
    members, raw_files = result
    if sorted(members) != ["control.tar.gz", "data.tar.gz", "debian-binary"]:
        raise ReleaseError(f"{label}: unerwartete Teile im Paket: {', '.join(sorted(members))}")
    if members["debian-binary"].strip() != b"2.0":
        raise ReleaseError(f"{label}: debian-binary ist nicht 2.0")

    files = [(name[2:] if name.startswith("./") else name.lstrip("/"), data) for name, data in raw_files]
    for name, _ in files:
        safe_member(name, label)
    check_names(label, (name for name, _ in files))
    by_name = dict(files)

    control = by_name.get("control")
    if control is None:
        raise ReleaseError(f"{label}: control fehlt")
    fields = dict(re.findall(r"^([A-Za-z-]+):[ \t]*(.*?)[ \t]*$", control.decode("utf-8", "replace"), re.MULTILINE))
    bundle_id = meta.bundle_ids["webos"]
    expect_equal(label, "Paketname (control)", fields.get("Package"), bundle_id)
    expect_equal(label, "Version (control)", fields.get("Version"), meta.version)

    appinfo_path = f"usr/palm/applications/{bundle_id}/appinfo.json"
    try:
        appinfo = json.loads(by_name[appinfo_path])
    except KeyError:
        raise ReleaseError(f"{label}: {appinfo_path} fehlt") from None
    except ValueError:
        raise ReleaseError(f"{label}: appinfo.json ist kein gültiges JSON") from None
    expect_equal(label, "Version (appinfo.json)", appinfo.get("version"), meta.version)
    expect_equal(label, "App-ID (appinfo.json)", appinfo.get("id"), bundle_id)
    # Das TV-Paket trägt genau ein Secret; welches, prüft check-webos-package.py --production.
    scan_contents(label, files, "ipk", patterns=True, secret_pattern_allowed=True)


def git_blobs(shas: list[str]) -> dict[str, bytes]:
    """Inhalte vieler Blobs in einem Aufruf."""
    if not shas:
        return {}
    result = run_git("cat-file", "--batch", binary=True, stdin=("\n".join(shas) + "\n").encode())
    if result.returncode != 0:
        raise ReleaseError("git cat-file fehlgeschlagen")
    out, blobs, position = result.stdout, {}, 0
    for sha in shas:
        end = out.index(b"\n", position)
        header = out[position:end].split()
        if len(header) != 3 or header[1] != b"blob":
            raise ReleaseError(f"Blob {sha[:7]} ist nicht lesbar")
        size = int(header[2])
        blobs[sha] = out[end + 1:end + 1 + size]
        position = end + 1 + size + 1
    return blobs


def source_tree(commit: str, key: str) -> dict[str, tuple[str, str]]:
    tree: dict[str, tuple[str, str]] = {}
    listing = git("ls-tree", "-r", "-z", "--full-tree", commit, "--", *SOURCE_PATHS[key])
    for record in listing.split("\0"):
        if not record:
            continue
        header, _, name = record.partition("\t")
        mode, kind, sha = header.split()
        if kind == "blob":
            tree[name] = (mode, sha)
    if not tree:
        raise ReleaseError(f"Commit {commit[:7]} enthält keine Quelldateien")
    return tree


def build_source_package(commit: str, output: Path, key: str = "macos") -> int:
    """Das Quellpaket aus dem Commit selbst — nicht aus der Arbeitskopie, Symlinks bleiben Symlinks."""
    tree = source_tree(commit, key)
    blobs = git_blobs(sorted({sha for _, sha in tree.values()}))
    seconds = int(git("show", "-s", "--format=%ct", commit).strip())
    stamp = max(dt.datetime.fromtimestamp(seconds, dt.timezone.utc), dt.datetime(1980, 1, 1, tzinfo=dt.timezone.utc))
    date_time = stamp.timetuple()[:6]
    with zipfile.ZipFile(output, "w") as archive:
        for name in sorted(tree):
            mode, sha = tree[name]
            info = zipfile.ZipInfo(name, date_time)
            info.create_system = 3
            if mode == "120000":
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                info.compress_type = zipfile.ZIP_STORED
            else:
                info.external_attr = (stat.S_IFREG | (0o755 if mode == "100755" else 0o644)) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, blobs[sha])
    return len(tree)


def verify_source_zip(meta: Meta, path: Path) -> None:
    """Jede Datei des Quellpakets ist Byte für Byte die des Commits — nicht mehr, nicht weniger."""
    label = path.name
    entries: dict[str, tuple[bytes, bool]] = {}
    with open_zip(path, label) as archive:
        for info in archive.infolist():
            safe_member(info.filename, label)
            if info.is_dir():
                continue
            entries[info.filename] = (archive.read(info), stat.S_ISLNK(info.external_attr >> 16))
    check_names(label, entries)

    tree = source_tree(meta.commit, "macos")
    extra = sorted(set(entries) - set(tree))
    if extra:
        raise ReleaseError(
            f"{label}: {len(extra)} Datei(en) gehören nicht zu Commit {meta.commit[:7]}, z. B. {', '.join(extra[:3])}"
        )
    missing = sorted(set(tree) - set(entries))
    if missing:
        raise ReleaseError(f"{label}: {len(missing)} Datei(en) des Commits fehlen, z. B. {', '.join(missing[:3])}")
    for name, (mode, sha) in sorted(tree.items()):
        data, is_link = entries[name]
        blob = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
        if blob != sha or (mode == "120000") != is_link:
            raise ReleaseError(f"{label}: {name} weicht vom Stand in {meta.commit[:7]} ab")

    project = XCODE_PROJECTS["macos"]
    text = entries[project][0].decode("utf-8", "replace")
    tool = version_tool()
    try:
        version = tool.single_setting(text, "MARKETING_VERSION", project)
        build = tool.single_setting(text, "CURRENT_PROJECT_VERSION", project)
    except tool.VersionError as error:
        raise ReleaseError(f"{label}: {error}") from None
    expect_equal(label, "MARKETING_VERSION", version, meta.version)
    expect_equal(label, "CURRENT_PROJECT_VERSION", build, meta.builds["macos"])
    # Kein Musterabgleich: die Tests im Quellpaket tragen absichtlich erfundene Tokens.
    scan_contents(label, ((name, data) for name, (data, _) in entries.items()), "source-zip", patterns=False)


# Windows ─────────────────────────────────────────────────────────────────────

VS_VERSION_INFO = "VS_VERSION_INFO\0".encode("utf-16-le")
FIXED_FILE_INFO = struct.pack("<I", 0xFEEF04BD)
NSIS_SIGNATURE = b"NullsoftInst"


def version_string(block: bytes, key: str) -> str | None:
    marker = (key + "\0").encode("utf-16-le")
    index = block.find(marker)
    while index != -1 and index % 2:
        index = block.find(marker, index + 1)
    if index == -1:
        return None
    start = index + len(marker)
    start += -start % 4
    end = start
    while end + 1 < len(block) and block[end:end + 2] != b"\0\0":
        end += 2
    return block[start:end].decode("utf-16-le", "replace")


def pe_version_info(data: bytes, label: str) -> tuple[tuple[int, ...], dict[str, str | None]]:
    """Produktversion aus VS_FIXEDFILEINFO und die Zeichenketten daneben."""
    if data[:2] != b"MZ" or len(data) < 0x40:
        raise ReleaseError(f"{label}: kein Windows-Programm")
    offset = int.from_bytes(data[0x3C:0x40], "little")
    if data[offset:offset + 4] != b"PE\0\0":
        raise ReleaseError(f"{label}: kein Windows-Programm (PE-Kopf fehlt)")
    index = data.find(VS_VERSION_INFO)
    while index != -1:
        start = index - 6
        signature = start + 40
        if start >= 0 and data[signature:signature + 4] == FIXED_FILE_INFO:
            length = int.from_bytes(data[start:start + 2], "little")
            product_ms, product_ls = struct.unpack_from("<II", data, signature + 16)
            product = (product_ms >> 16, product_ms & 0xFFFF, product_ls >> 16, product_ls & 0xFFFF)
            block = data[start:start + length]
            return product, {key: version_string(block, key) for key in ("ProductVersion", "FileVersion", "ProductName")}
        index = data.find(VS_VERSION_INFO, index + 2)
    raise ReleaseError(f"{label}: keine Versionsangaben (VS_VERSION_INFO) – Windows würde keine Version anzeigen")


def check_pe_version(label: str, data: bytes, version: str) -> None:
    product, strings = pe_version_info(data, label)
    if product[:3] != version_key(version):
        shown = ".".join(str(part) for part in product)
        raise ReleaseError(f"{label}: Produktversion {shown}, der Release verlangt {version}")
    value = strings.get("ProductVersion")
    if value is not None and value != version and not value.startswith(version + "."):
        raise ReleaseError(f"{label}: ProductVersion {value!r}, der Release verlangt {version}")


def read_asar(data: bytes, label: str) -> dict[str, bytes]:
    """Dateien aus einem Electron-`app.asar`. Ausgelagerte (`unpacked`) Dateien liegen daneben."""
    try:
        header_size = struct.unpack_from("<I", data, 4)[0]
        json_size = struct.unpack_from("<i", data, 12)[0]
        header = json.loads(data[16:16 + json_size].decode("utf-8"))
    except (struct.error, ValueError, UnicodeDecodeError):
        raise ReleaseError(f"{label}: app.asar ist nicht lesbar") from None
    base = 8 + header_size
    files: dict[str, bytes] = {}

    def walk(node: dict, prefix: str) -> None:
        for name, entry in (node.get("files") or {}).items():
            path = prefix + name
            safe_member(path, label)
            if not isinstance(entry, dict):
                raise ReleaseError(f"{label}: app.asar ist nicht lesbar ({path})")
            if "files" in entry:
                walk(entry, path + "/")
                continue
            if entry.get("unpacked") or "link" in entry:
                continue
            try:
                start = base + int(entry["offset"])
                end = start + int(entry["size"])
            except (KeyError, TypeError, ValueError):
                raise ReleaseError(f"{label}: app.asar ist nicht lesbar ({path})") from None
            if start < base or end > len(data):
                raise ReleaseError(f"{label}: app.asar ist abgeschnitten ({path})")
            files[path] = data[start:end]

    walk(header, "")
    return files


def verify_windows_installer(meta: Meta, path: Path) -> None:
    label = path.name
    data = path.read_bytes()
    check_pe_version(label, data, meta.version)
    if NSIS_SIGNATURE not in data:
        raise ReleaseError(f"{label}: kein NSIS-Installer")
    # Der Inhalt ist komprimiert; wiedererkannt werden nur unverpackte fremde
    # Werte. Den Inhalt selbst prüft das ZIP aus demselben Build.
    scan_contents(label, [(label, data)], "windows-installer", patterns=False,
                  allowed_values=desktop_credentials().values())


def windows_app_files(path: Path, label: str) -> tuple[dict[str, bytes], list[str]]:
    with open_zip(path, label) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        for name in names:
            safe_member(name, label)
        check_names(label, names)
        members = {info.filename for info in infos if not info.is_dir()}
        for required in ("Nori.exe", "resources/app.asar"):
            if required not in members:
                raise ReleaseError(f"{label}: {required} fehlt – das ZIP muss den Programmordner selbst enthalten")
        asar = read_asar(archive.read("resources/app.asar"), f"{label}: resources/app.asar")
    return asar, sorted(members)


def verify_windows_portable(meta: Meta, path: Path) -> None:
    label = path.name
    asar, members = windows_app_files(path, label)
    try:
        package = json.loads(asar["package.json"])
    except KeyError:
        raise ReleaseError(f"{label}: package.json fehlt in app.asar") from None
    except ValueError:
        raise ReleaseError(f"{label}: package.json in app.asar ist kein gültiges JSON") from None
    expect_equal(label, "Version (app.asar/package.json)", package.get("version"), meta.version)
    expect_equal(label, "Paketname (app.asar/package.json)", package.get("name"), "@nori/windows")
    for required in ("dist/index.html", str(package.get("main") or "dist-main/main.cjs")):
        if required not in asar:
            raise ReleaseError(f"{label}: {required} fehlt in app.asar")

    allowed = desktop_credentials().values()
    # Muster nur im eigenen Code: Chromium und Node bringen Zeichenketten mit,
    # die wie Beispielwerte aussehen. Fremde echte Werte werden überall gesucht.
    scan_contents(label, ((f"app.asar/{name}", data) for name, data in asar.items()), "windows-portable",
                  patterns=True, allowed_values=allowed, secret_pattern_allowed=True)
    with open_zip(path, label) as archive:
        check_pe_version(f"{label}: Nori.exe", archive.read("Nori.exe"), meta.version)
        scan_contents(label, ((name, archive.read(name)) for name in members), "windows-portable",
                      patterns=False, allowed_values=allowed)


def check_windows_credentials(path: Path) -> None:
    """Ein Windows-Release ohne eingebauten Google-Client hätte keinen Abgleich."""
    values = desktop_credentials()
    missing = [name for name in DESKTOP_CLIENT_ENV if name not in values]
    if missing:
        raise ReleaseError(
            f"Für das Windows-Paket fehlen {', '.join(missing)} – ohne sie hätte Nori für Windows keinen "
            "Google-Abgleich. Repository-Secrets anlegen (docs/windows.md) oder Windows im Release abwählen."
        )
    asar, _ = windows_app_files(path, path.name)
    code = b"".join(data for name, data in asar.items() if name.endswith((".cjs", ".js")))
    for name, value in values.items():
        if value.encode() not in code:
            raise ReleaseError(f"{path.name}: {name} ist nicht in den Hauptprozess eingebaut")
    print(f"  {path.name}: Google-Desktop-Client eingebaut")


def production_check(meta: Meta, spec: AssetSpec, path: Path) -> None:
    """Die Produktionsprüfung der Plattform — gegen genau diese Datei."""
    if spec.kind == "windows-portable":
        check_windows_credentials(path)
        return
    if spec.kind == "ipa":
        command = [sys.executable, str(ROOT / "tools/configure-google-oauth.py"), "--verify-ios-ipa", str(path)]
    elif spec.kind == "ipk":
        command = [sys.executable, str(ROOT / "tools/check-webos-package.py"), "--production", "--ipk", str(path)]
    else:
        # Quellpaket: verify_source_zip hat jede Datei mit dem Commit verglichen.
        # Installer: sein Inhalt ist der des geprüften ZIP aus demselben Build.
        return
    # CI=true: die Werkzeuge kürzen Client-IDs dann auch außerhalb der CI.
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, env={**os.environ, "CI": "true"})
    lines = [line for line in result.stdout.splitlines() if line.strip() and not line.startswith("WARN")]
    for line in lines[-8:]:
        print(f"  {line}")
    if result.returncode != 0:
        raise ReleaseError(f"Produktionsprüfung für {path.name} fehlgeschlagen – kein Release")


def check_app(platform: str, app: Path, meta: Meta) -> None:
    """Das gebaute Programm trägt Version, Build und Kennung des Commits."""
    plist = app / ("Contents/Info.plist" if platform == "macos" else "Info.plist")
    try:
        info = plistlib.loads(plist.read_bytes())
    except FileNotFoundError:
        raise ReleaseError(f"{plist} fehlt") from None
    except Exception as error:
        raise ReleaseError(f"{plist} ist nicht lesbar ({type(error).__name__})") from None
    label = f"{app.name} ({platform})"
    expect_equal(label, "CFBundleShortVersionString", info.get("CFBundleShortVersionString"), meta.version)
    expect_equal(label, "CFBundleVersion", info.get("CFBundleVersion"), meta.builds[platform])
    expect_equal(label, "CFBundleIdentifier", info.get("CFBundleIdentifier"), meta.bundle_ids[platform])


# ── Release Notes ────────────────────────────────────────────────────────────

# Was in öffentliche Notes nicht gehört. Ein Satz oder Punkt, der eines davon
# nennt, fällt heraus — bei Punkten mit fetter Überschrift bleibt die Überschrift.
SENSITIVE = re.compile(
    r"secret|client[-_ ]?id|oauth|\.env\b|xcconfig|\.config/|token|VITE_|GOOGLE_CLIENT|GoogleClient"
    r"|device[-_ ]?code|user[-_ ]?code|cookie|googleusercontent|GOCSPX|zugangsdaten|credential|runner",
    re.IGNORECASE,
)
PUBLIC_SECTIONS = {
    "Allgemein", "iOS / iPadOS", "iOS", "macOS", "Android / Google TV", "Windows", "webOS", "LG webOS",
    "Technische Änderungen", "Behoben", "Geändert", "Hinzugefügt", "Neu", "Entfernt", "Verbessert",
    "Sicherheit", "Bekannte Einschränkungen", "Hinweis zum Update",
}
BULLET = re.compile(r"^[-*] ")
SUB_BULLET = re.compile(r"^\s+[-*] ")
ABBREVIATION = re.compile(r"(?:\b(?:z|B|d|h|u|a|bzw|ca|inkl|vgl|Nr|evtl|ggf|usw|etc|max|min|Std|Sek|Min)|\d)\.$")


def changelog_tool():
    return load_tool("changelog_section", "changelog-section.py")


def section_applies(heading: str) -> bool:
    """`### Windows` gehört in die Notes, `### Tests` nicht."""
    base = re.split(r"\s+[—–]\s+", heading.lstrip("#").strip(), maxsplit=1)[0].strip()
    return base in PUBLIC_SECTIONS


def sentences(text: str) -> list[str]:
    # Satzanfänge: Großbuchstabe, Auszeichnung — oder ein Plattformname wie „iOS".
    parts = re.split(r"(?<=[.!?…])\s+(?=[A-ZÄÖÜ„\"*`(\[]|iOS\b|iPadOS\b|macOS\b|webOS\b)", text)
    merged: list[str] = []
    for part in parts:
        if merged and ABBREVIATION.search(merged[-1]):
            merged[-1] = f"{merged[-1]} {part}"
        else:
            merged.append(part)
    return merged


def public_paragraph(text: str) -> str:
    return " ".join(sentence for sentence in sentences(text) if not SENSITIVE.search(sentence))


def public_bullet(lines: list[str]) -> list[tuple[str, str]]:
    main = [lines[0][2:].strip()]
    subs: list[list[str]] = []
    for line in lines[1:]:
        if SUB_BULLET.match(line):
            subs.append([line.strip()[2:].strip()])
        elif subs:
            subs[-1].append(line.strip())
        else:
            main.append(line.strip())
    text = " ".join(main)
    if SENSITIVE.search(text):
        lead = re.match(r"^\*\*(.+?)\*\*", text)
        if not lead or SENSITIVE.search(lead.group(0)):
            return []
        return [("bullet", f"- {lead.group(0)}")]
    out = [("bullet", f"- {text}")]
    for sub in subs:
        sub_text = " ".join(sub)
        if not SENSITIVE.search(sub_text):
            out.append(("bullet", f"  - {sub_text}"))
    return out


def public_changes(section: str) -> str:
    """Die öffentlichen Teile eines Changelog-Abschnitts."""
    lines = section.splitlines()
    groups: list[tuple[str | None, list[tuple[str, str]]]] = [(None, [])]
    include = True
    index = 0
    while index < len(lines):
        line = lines[index]
        stripped = line.strip()
        if stripped.startswith("```"):
            index += 1
            while index < len(lines) and not lines[index].strip().startswith("```"):
                index += 1
            index += 1
            continue
        if line.startswith("### "):
            include = section_applies(line)
            groups.append((stripped, []))
            index += 1
            continue
        blocks = groups[-1][1]
        if not stripped:
            index += 1
            continue
        if line.startswith("#"):
            if include and not SENSITIVE.search(stripped):
                blocks.append(("paragraph", f"**{stripped.lstrip('#').strip()}**"))
            index += 1
            continue
        if BULLET.match(line):
            item = [line]
            index += 1
            while index < len(lines) and lines[index].strip() and lines[index][0].isspace():
                item.append(lines[index])
                index += 1
            if include:
                blocks.extend(public_bullet(item))
            continue
        if stripped.startswith("|"):
            table = []
            while index < len(lines) and lines[index].strip().startswith("|"):
                table.append(lines[index].strip())
                index += 1
            if include and not any(SENSITIVE.search(row) for row in table):
                blocks.append(("paragraph", "\n".join(table)))
            continue
        paragraph = []
        while index < len(lines):
            current = lines[index]
            if (not current.strip() or BULLET.match(current) or current.startswith("#")
                    or current.strip().startswith(("```", "|"))):
                break
            paragraph.append(current.strip())
            index += 1
        if include:
            text = public_paragraph(" ".join(paragraph))
            if text:
                blocks.append(("paragraph", text))

    rendered = []
    for heading, blocks in groups:
        if not blocks:
            continue
        body: list[str] = []
        for position, (kind, text) in enumerate(blocks):
            if position and not (kind == "bullet" and blocks[position - 1][0] == "bullet"):
                body.append("")
            body.append(text)
        rendered.append("\n".join(([heading, ""] if heading else []) + body))
    return "\n\n".join(rendered)


def check_public_text(text: str) -> None:
    """Letzte Sperre vor der Veröffentlichung der Notes."""
    data = text.encode()
    if SENSITIVE.search(text):
        raise ReleaseError("Release Notes nennen interne OAuth-/Secret-Einzelheiten – kein Release")
    if CLIENT_ID_ANY.search(data) or CLIENT_SECRET_ANY.search(data):
        raise ReleaseError("Release Notes enthalten eine Client-ID oder ein Client-Secret – kein Release")
    for pattern, what in TOKEN_PATTERNS:
        if pattern.search(data):
            raise ReleaseError(f"Release Notes enthalten ein {what} – kein Release")
    for origin, value in known_credentials().items():
        if value in text:
            raise ReleaseError(f"Release Notes enthalten Zugangsdaten aus {origin} – kein Release")


def build_notes(meta: Meta, platforms: list[str], repository: str) -> str:
    changelog = file_at(meta.commit, "CHANGELOG.md")
    section = changelog_tool().extract(changelog, "Nori", meta.version)
    if section is None:
        raise ReleaseError(f"CHANGELOG.md hat in {meta.commit[:7]} keinen Abschnitt [Nori {meta.version}] – kein Release")
    changes = public_changes(section) or "Keine gesonderten Hinweise; Einzelheiten stehen in `CHANGELOG.md`."

    rows = ["| Plattform | Datei | Hinweis |", "| --- | --- | --- |"]
    for platform in platforms:
        for key in PLATFORMS[platform].assets:
            spec = ASSETS[key]
            build = meta.builds.get(platform)
            hint = (f"Build {build}. " if build else "") + spec.hint
            rows.append(f"| {spec.label} | `{spec.name(meta.version)}` | {hint} |")
    missing = [f"{PLATFORMS[key].display} (für diesen Release nicht gebaut)" for key in PLATFORMS if key not in platforms]
    missing += [f"{name} ({reason})" for name, reason in NOT_AVAILABLE.items()]
    included = ", ".join(PLATFORMS[key].display for key in platforms)

    notes = "\n".join([
        f"**Nori {meta.version}** für {included} – eine Versionsnummer für alle Plattformen.",
        "",
        f"Commit [`{meta.commit[:7]}`](https://github.com/{repository}/commit/{meta.commit})",
        "",
        *rows,
        "",
        f"Nicht enthalten: {', '.join(missing)}.",
        "",
        f"Prüfsummen stehen in `{CHECKSUMS}` – nach dem Herunterladen im selben Ordner: "
        f"`shasum -a 256 -c {CHECKSUMS}`",
        "",
        "## Änderungen",
        "",
        changes,
        "",
    ])
    check_public_text(notes)
    return notes


# ── GitHub ───────────────────────────────────────────────────────────────────

SYSTEM_CA_FILE = Path("/etc/ssl/cert.pem")


def https_context() -> ssl.SSLContext:
    """Zertifikate werden immer geprüft.

    Das Python von python.org — auf dem Runner das erste `python3` im PATH —
    bringt auf macOS keine CA-Liste mit, solange „Install Certificates" nicht
    gelaufen ist; jeder HTTPS-Aufruf scheitert dann. In dem Fall gilt die
    CA-Liste des Systems. `SSL_CERT_FILE` hat weiter Vorrang.
    """
    paths = ssl.get_default_verify_paths()
    if not (paths.cafile or paths.capath) and SYSTEM_CA_FILE.is_file():
        return ssl.create_default_context(cafile=str(SYSTEM_CA_FILE))
    return ssl.create_default_context()


# Das Einzige, was dieses Werkzeug löschen darf.
DELETABLE = re.compile(r"^/repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/(runs|artifacts)/[1-9]\d*$")

# Störungen, die beim nächsten Versuch weg sind: ein abgeschnittener
# Antwortkörper oder eine Verbindung, die nicht zustande kam.
TRANSIENT = (http.client.IncompleteRead, http.client.RemoteDisconnected, ConnectionError, TimeoutError)
RETRIES = 3
RETRY_PAUSE = 2.0


class GitHub:
    """Die wenigen REST-Aufrufe, die Release und Aufräumen brauchen."""

    def __init__(self, repository: str, token: str, api: str = "https://api.github.com",
                 uploads: str = "https://uploads.github.com", opener: urllib.request.OpenerDirector | None = None):
        if not token:
            raise ReleaseError("GITHUB_TOKEN fehlt")
        self.repository = repository
        self._token = token
        self.api = api.rstrip("/")
        self.uploads = uploads.rstrip("/")
        self._opener = opener or urllib.request.build_opener(urllib.request.HTTPSHandler(context=https_context()))

    def __repr__(self) -> str:
        return f"GitHub({self.repository})"

    def request(self, method: str, url: str, payload: object = None, data: bytes | None = None,
                content_type: str | None = None, accept: str = "application/vnd.github+json",
                missing_ok: bool = False, raw: bool = False):
        """Ein Aufruf; lesende werden bei einer Störung wiederholt.

        Wiederholt wird nur, was sich gefahrlos wiederholen lässt: `GET` und
        `DELETE`. Ein zweites `POST` könnte einen zweiten Entwurf, einen
        zweiten Anhang oder einen zweiten Tag anlegen — lieber ein roter Lauf
        als das.

        Der Anlass: Beim Aufräumen von rund 900 Läufen brach GitHub die
        Antwort einer Liste mitten im Körper ab (`IncompleteRead`), und der
        Lauf endete an einer Stelle, an der nichts falsch war.
        """
        attempts = RETRIES if method in ("GET", "DELETE") else 1
        for attempt in range(1, attempts + 1):
            try:
                return self._once(method, url, payload, data, content_type, accept, missing_ok, raw)
            except TRANSIENT as error:
                if attempt == attempts:
                    raise
                reason = f"{type(error).__name__}: {error}"
            except GitHubError as error:
                # 0 heißt „nicht erreichbar", 5xx „gerade nicht". Alles andere
                # — 404, 422, eine Bremse — ist eine Antwort und keine Störung.
                if attempt == attempts or not (error.status == 0 or error.status >= 500):
                    raise
                reason = str(error)
            pause = RETRY_PAUSE * attempt
            print(f"  {reason} – noch einmal in {pause:.0f} s ({attempt}/{attempts - 1})")
            time.sleep(pause)

    def _once(self, method: str, url: str, payload: object, data: bytes | None,
              content_type: str | None, accept: str, missing_ok: bool, raw: bool):
        if not url.startswith("http"):
            url = f"{self.api}/repos/{self.repository}{url}"
        path = urllib.parse.urlsplit(url).path
        if method == "DELETE" and not DELETABLE.match(path):
            raise ReleaseError(f"Löschen ist nur für Workflow-Läufe und -Artefakte vorgesehen, nicht für {path}")
        headers = {"Accept": accept, "User-Agent": "nori-release", "X-GitHub-Api-Version": "2022-11-28"}
        if payload is not None:
            data = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
        if content_type:
            headers["Content-Type"] = content_type
        request = urllib.request.Request(url, data=data, method=method, headers=headers)
        # Nur an GitHub selbst: folgt ein Download einer Weiterleitung zum
        # Speicher, geht das Token nicht mit.
        request.add_unredirected_header("Authorization", f"Bearer {self._token}")
        try:
            with self._opener.open(request, timeout=300) as response:
                content = response.read()
        except urllib.error.HTTPError as error:
            with error:
                body = error.read()
            if error.code == 404 and missing_ok:
                return None
            detail = ""
            try:
                detail = str(json.loads(body or b"{}").get("message", ""))
            except (ValueError, AttributeError):
                pass
            headers_in = error.headers or {}
            limited = error.code in (403, 429) and (
                "rate limit" in detail.lower() or headers_in.get("x-ratelimit-remaining") == "0"
                or headers_in.get("retry-after") is not None
            )
            raise GitHubError(error.code, f"GitHub {method} {path}: HTTP {error.code} {detail[:200]}".rstrip(),
                              rate_limited=limited) from None
        except urllib.error.URLError as error:
            raise GitHubError(0, f"GitHub {method} nicht erreichbar: {error.reason}") from None
        if raw:
            return content
        return json.loads(content) if content else None

    def paged(self, path: str, key: str | None = None, limit: int = 50) -> list[dict]:
        found: list[dict] = []
        separator = "&" if "?" in path else "?"
        for page in range(1, limit + 1):
            batch = self.request("GET", f"{path}{separator}per_page=100&page={page}") or ([] if key is None else {})
            items = batch if key is None else batch.get(key, [])
            found.extend(items)
            if len(items) < 100:
                break
        return found

    # Release ────────────────────────────────────────────────────────────────

    def tag_commit(self, tag: str) -> str | None:
        ref = self.request("GET", f"/git/ref/tags/{urllib.parse.quote(tag)}", missing_ok=True)
        if ref is None:
            return None
        if isinstance(ref, list):
            ref = next((item for item in ref if item.get("ref") == f"refs/tags/{tag}"), None)
            if ref is None:
                return None
        target = ref["object"]
        for _ in range(5):
            if target["type"] == "commit":
                return target["sha"]
            if target["type"] != "tag":
                raise ReleaseError(f"Tag {tag} zeigt nicht auf einen Commit")
            target = self.request("GET", f"/git/tags/{target['sha']}")["object"]
        raise ReleaseError(f"Tag {tag} ist zu tief verschachtelt")

    def tags(self) -> list[str]:
        refs = self.request("GET", "/git/matching-refs/tags/") or []
        return [item["ref"].removeprefix("refs/tags/") for item in refs]

    def releases(self) -> list[dict]:
        return self.paged("/releases")

    def on_main(self, commit: str) -> bool:
        comparison = self.request("GET", f"/compare/main...{commit}")
        return comparison.get("status") in ("identical", "behind") and comparison.get("ahead_by") == 0

    def create_draft(self, meta: Meta, notes: str) -> dict:
        return self.request("POST", "/releases", {
            "tag_name": meta.tag, "target_commitish": meta.commit, "name": meta.title,
            "body": notes, "draft": True, "prerelease": False,
        })

    def upload(self, release: dict, path: Path, name: str, content_type: str) -> dict:
        url = (f"{self.uploads}/repos/{self.repository}/releases/{release['id']}/assets"
               f"?name={urllib.parse.quote(name)}")
        return self.request("POST", url, data=path.read_bytes(), content_type=content_type)

    def assets(self, release: dict) -> list[dict]:
        return self.paged(f"/releases/{release['id']}/assets")

    def download_asset(self, asset: dict) -> bytes:
        return self.request("GET", f"/releases/assets/{asset['id']}", accept="application/octet-stream", raw=True)

    def create_tag(self, tag: str, commit: str, message: str) -> None:
        tag_object = self.request("POST", "/git/tags", {"tag": tag, "message": message, "object": commit, "type": "commit"})
        # Legt die Referenz an; gibt es sie schon, antwortet GitHub mit 422 — verschoben wird nichts.
        self.request("POST", "/git/refs", {"ref": f"refs/tags/{tag}", "sha": tag_object["sha"]})

    def publish(self, release: dict) -> dict:
        return self.request("PATCH", f"/releases/{release['id']}", {"draft": False, "make_latest": "true"})

    def release_by_tag(self, tag: str) -> dict | None:
        return self.request("GET", f"/releases/tags/{urllib.parse.quote(tag)}", missing_ok=True)

    # Actions ────────────────────────────────────────────────────────────────

    def run(self, run_id: int) -> dict:
        return self.request("GET", f"/actions/runs/{int(run_id)}")

    def workflows(self) -> list[dict]:
        return self.paged("/actions/workflows", key="workflows")

    def workflow_runs(self, workflow_id: int) -> list[dict]:
        return self.paged(f"/actions/workflows/{int(workflow_id)}/runs", key="workflow_runs")

    def artifacts(self, run_id: int) -> list[dict]:
        return self.paged(f"/actions/runs/{int(run_id)}/artifacts", key="artifacts")

    def open_pull_heads(self) -> set[str]:
        return {str(pull["head"]["sha"]) for pull in self.paged("/pulls?state=open")}

    def delete_run(self, run_id: int) -> None:
        self.request("DELETE", f"/actions/runs/{int(run_id)}")

    def delete_artifact(self, artifact_id: int) -> None:
        self.request("DELETE", f"/actions/artifacts/{int(artifact_id)}")


def repository_name() -> str:
    value = os.environ.get("GITHUB_REPOSITORY", "")
    if not value:
        url = git("remote", "get-url", "origin").strip()
        match = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?$", url)
        value = match.group(1) if match else ""
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ReleaseError("GitHub-Repository nicht erkennbar (GITHUB_REPOSITORY fehlt)")
    return value


def github_from_environment() -> GitHub:
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    return GitHub(repository_name(), token)


# ── Vorbereiten, veröffentlichen, nachprüfen ─────────────────────────────────


def decide(meta: Meta, tag_commit: str | None, releases: list[dict], tags: list[str]) -> None:
    """Nur eine neue, höhere Version wird veröffentlicht — sonst Abbruch, nie Verschieben."""
    same = [release for release in releases if release.get("tag_name") == meta.tag or release.get("name") == meta.title]
    if any(not release.get("draft") for release in same):
        raise ReleaseError(
            f"Release {meta.title} existiert bereits – kein zweiter Release. "
            "Für einen neuen Stand zuerst die Version erhöhen (python3 tools/nori-version.py bump …)."
        )
    if same:
        raise ReleaseError(
            f"Für {meta.tag} liegt ein unveröffentlichter Entwurf – er wird weder überschrieben noch gelöscht. "
            "Bitte unter Releases ansehen, von Hand entfernen und den Lauf neu starten."
        )
    if tag_commit is not None:
        raise ReleaseError(f"Tag {meta.tag} existiert bereits (auf {tag_commit[:7]}) – er wird nicht verschoben, kein Release.")
    names = {*tags, *(str(release.get("tag_name") or "") for release in releases)}
    taken = sorted(
        ((version, name) for name in names if (version := tag_version(name))
         and version_key(version) >= version_key(meta.version)),
        key=lambda item: (version_key(item[0]), item[1]),
    )
    if taken:
        version, name = taken[-1]
        if version == meta.version:
            raise ReleaseError(f"Version {meta.version} ist unter {name} bereits vergeben – bitte eine höhere Version setzen.")
        raise ReleaseError(f"{meta.tag} ist nicht neuer als das vorhandene {name} – bitte eine höhere Version setzen.")


def in_actions() -> bool:
    return bool(os.environ.get("GITHUB_ACTIONS"))


def require_main() -> None:
    if in_actions() and os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise ReleaseError(
            f"Releases entstehen nur auf main – dieser Lauf läuft auf {os.environ.get('GITHUB_REF') or '?'}. "
            "Unter „Use workflow from“ main wählen."
        )


def prepare(version_input: str, platforms_input: str | Iterable[str], github, ref: str = "HEAD") -> tuple[Meta, list[str]]:
    """Alles, was sich vor dem Bauen prüfen lässt."""
    version = normalize_version(version_input)
    platforms = parse_platforms(platforms_input)
    require_main()
    meta = read_meta(ref, version)
    check_documents(meta)
    tags = github.tags()
    decide(meta, github.tag_commit(meta.tag), github.releases(), tags)
    check_builds(meta, tags)
    return meta, platforms


def collect_assets(directory: Path, meta: Meta, platforms: list[str]) -> list[tuple[AssetSpec, Path]]:
    """Genau die Pakete der gewählten Plattformen — keins fehlt, keins zu viel."""
    if not directory.is_dir():
        raise ReleaseError(f"Ordner mit den Paketen fehlt: {directory}")
    found: dict[str, Path] = {}
    for path in sorted(directory.rglob("*")):
        if path.is_dir():
            continue
        if path.name in found:
            raise ReleaseError(f"{path.name} liegt doppelt vor")
        found[path.name] = path
    expected = expected_assets(meta.version, platforms)
    missing = sorted(set(expected) - set(found))
    if missing:
        raise ReleaseError(f"Es fehlen Pakete: {', '.join(missing)} – kein Release")
    extra = sorted(set(found) - set(expected))
    if extra:
        raise ReleaseError(f"Unerwartete Dateien bei den Paketen: {', '.join(extra[:5])} – kein Release")
    return [(expected[name], found[name]) for name in expected]


def checksum_text(digests: dict[str, str]) -> str:
    return "".join(f"{digests[name]}  {name}\n" for name in sorted(digests))


def parse_checksums(text: str) -> dict[str, str]:
    sums: dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        match = re.fullmatch(r"([0-9a-f]{64}) [ *](.+)", line)
        if not match or match.group(2) in sums:
            raise ReleaseError(f"{CHECKSUMS}: unlesbare Zeile {line[:80]!r}")
        sums[match.group(2)] = match.group(1)
    return sums


def check_uploaded(github, release: dict, expected: dict[str, tuple[int, str]], label: str) -> None:
    assets = github.assets(release)
    names = sorted(item.get("name") for item in assets)
    if names != sorted(expected):
        raise ReleaseError(f"{label} trägt unerwartete Anhänge ({', '.join(names)}) – wird nicht veröffentlicht")
    for item in assets:
        size, digest = expected[item["name"]]
        if item.get("state") != "uploaded" or item.get("size") != size:
            raise ReleaseError(f"Anhang {item['name']} ist unvollständig hochgeladen – {label} wird nicht veröffentlicht")
        remote = item.get("digest")
        matches = (remote == f"sha256:{digest}") if remote else (hashlib.sha256(github.download_asset(item)).hexdigest() == digest)
        if not matches:
            raise ReleaseError(f"Hochgeladener Anhang {item['name']} weicht vom geprüften Paket ab – {label} wird nicht veröffentlicht")


def write_summary(lines: list[str]) -> None:
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if target:
        with open(target, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")


def run_release(meta: Meta, platforms: list[str], directory: Path, github, checksums: dict[str, str],
                repository: str, dry_run: bool = False) -> str:
    decide(meta, github.tag_commit(meta.tag), github.releases(), github.tags())
    assets = collect_assets(directory, meta, platforms)
    missing = [spec.key for spec, _ in assets if spec.key not in checksums]
    if missing:
        raise ReleaseError(f"Prüfsumme aus dem Paket-Job fehlt für {', '.join(missing)} – kein Release")

    digests: dict[str, str] = {}
    for spec, path in assets:
        digests[path.name] = verify_asset(meta, spec, path, checksums[spec.key])
        print(f"Paket geprüft: {path.name} ({path.stat().st_size} Bytes, sha256 {digests[path.name]})")
        production_check(meta, spec, path)
    sums = checksum_text(digests)
    notes = build_notes(meta, platforms, repository)
    if not github.on_main(meta.commit):
        raise ReleaseError(f"Commit {meta.commit[:7]} liegt nicht auf main – kein Release.")
    if dry_run:
        print(f"\nProbelauf: {meta.title} würde mit {len(assets)} Paketen und {CHECKSUMS} auf {meta.commit[:7]} angelegt.\n")
        print(sums)
        print(notes)
        return "dry-run"

    # Erst ein unsichtbarer Entwurf mit geprüften Anhängen, dann der Tag, dann
    # die Veröffentlichung. Scheitert ein Schritt, bleibt nichts Halbes
    # öffentlich stehen, und der nächste Lauf bricht mit einer klaren Meldung ab.
    with tempfile.TemporaryDirectory(prefix="nori-checksums-") as temp:
        sums_path = Path(temp) / CHECKSUMS
        sums_path.write_text(sums, encoding="utf-8")
        draft = github.create_draft(meta, notes)
        expected: dict[str, tuple[int, str]] = {}
        for spec, path in assets:
            github.upload(draft, path, path.name, spec.content_type)
            expected[path.name] = (path.stat().st_size, digests[path.name])
        github.upload(draft, sums_path, CHECKSUMS, "text/plain")
        expected[CHECKSUMS] = (sums_path.stat().st_size, sha256_file(sums_path))
    check_uploaded(github, draft, expected, f"Entwurf {meta.tag}")

    message = meta.title + "".join(f" · {platform} {build}" for platform, build in meta.builds.items() if platform in platforms)
    try:
        github.create_tag(meta.tag, meta.commit, message)
    except GitHubError as error:
        if error.status == 422:
            raise ReleaseError(
                f"Tag {meta.tag} ist inzwischen vorhanden – nicht verschoben; der Entwurf bleibt zur Prüfung liegen."
            ) from None
        raise
    if github.tag_commit(meta.tag) != meta.commit:
        raise ReleaseError(f"Tag {meta.tag} zeigt nicht auf {meta.commit[:7]} – Entwurf wird nicht veröffentlicht.")
    github.publish(draft)

    final = github.release_by_tag(meta.tag)
    if not final or final.get("draft") or final.get("id") != draft.get("id"):
        raise ReleaseError(f"Release {meta.tag} ist nach dem Veröffentlichen nicht auffindbar")
    print(f"Release angelegt: {meta.title} – {final.get('html_url', '')}")
    write_summary([f"## {meta.title}", "", f"{final.get('html_url', '')}", "", "| Datei | SHA-256 |", "| --- | --- |",
                   *(f"| `{name}` | `{digest}` |" for name, digest in sorted(digests.items()))])
    return "created"


def validate_release(github, meta: Meta, platforms: list[str]) -> dict:
    """Existiert der Release, zeigt der Tag auf den Commit, sind alle Pakete vollständig da?"""
    release = github.release_by_tag(meta.tag)
    if not release:
        raise ReleaseError(f"Release {meta.tag} nicht gefunden")
    if release.get("draft") or release.get("prerelease"):
        raise ReleaseError(f"Release {meta.tag} ist nicht veröffentlicht")
    if release.get("name") != meta.title:
        raise ReleaseError(f"Release {meta.tag} heißt {release.get('name')!r}, erwartet {meta.title!r}")
    tag_commit = github.tag_commit(meta.tag)
    if tag_commit != meta.commit:
        raise ReleaseError(f"Tag {meta.tag} zeigt auf {str(tag_commit)[:7]}, erwartet {meta.commit[:7]}")

    expected = set(expected_assets(meta.version, platforms))
    assets = {item["name"]: item for item in github.assets(release)}
    missing = sorted((expected | {CHECKSUMS}) - set(assets))
    extra = sorted(set(assets) - expected - {CHECKSUMS})
    if missing or extra:
        details = "; ".join(part for part in (
            f"fehlt: {', '.join(missing)}" if missing else "", f"zu viel: {', '.join(extra)}" if extra else "") if part)
        raise ReleaseError(f"Release {meta.tag} ist unvollständig – {details}")
    for name, item in assets.items():
        if item.get("state") != "uploaded" or not item.get("size"):
            raise ReleaseError(f"Anhang {name} ist nicht vollständig hochgeladen")

    raw = github.download_asset(assets[CHECKSUMS])
    remote = assets[CHECKSUMS].get("digest")
    if remote and remote != f"sha256:{hashlib.sha256(raw).hexdigest()}":
        raise ReleaseError(f"{CHECKSUMS} weicht von der Prüfsumme bei GitHub ab")
    sums = parse_checksums(raw.decode("utf-8"))
    if set(sums) != expected:
        raise ReleaseError(f"{CHECKSUMS} nennt {', '.join(sorted(sums))}, erwartet {', '.join(sorted(expected))}")
    for name in sorted(expected):
        remote = assets[name].get("digest")
        actual = remote.removeprefix("sha256:") if remote else hashlib.sha256(github.download_asset(assets[name])).hexdigest()
        if actual != sums[name]:
            raise ReleaseError(f"{name}: Prüfsumme bei GitHub weicht von {CHECKSUMS} ab")
    print(f"Release geprüft: {meta.title} – {len(expected)} Pakete und {CHECKSUMS}, Tag auf {meta.commit[:7]}")
    return release


# ── Aufräumen ────────────────────────────────────────────────────────────────

RELEASE_WORKFLOW = ".github/workflows/release.yml"

# Nur Läufe dieser Workflows werden gelöscht: Plattform-Builds, Pakete, der
# Release selbst und die Prüfläufe, die er ebenfalls ausführt. Die Namen
# entfernter Dateien bleiben stehen, weil ihre alten Läufe noch in Actions
# liegen. Ein neuer Workflow — etwa CodeQL, Dependabot oder eine Wartung — ist
# nicht dabei, bis ihn jemand ausdrücklich hier einträgt.
CLEANUP_WORKFLOWS = frozenset({
    RELEASE_WORKFLOW,
    ".github/workflows/build-ios.yml",
    ".github/workflows/build-macos.yml",
    ".github/workflows/build-webos.yml",
    ".github/workflows/build-windows.yml",
    ".github/workflows/build-android.yml",
    ".github/workflows/swift-tests.yml",
    ".github/workflows/check-sources.yml",
    ".github/workflows/check-release.yml",
    # entfernt, Läufe noch vorhanden
    ".github/workflows/package-ios-ipa.yml",
    ".github/workflows/package-macos-source.yml",
    ".github/workflows/build-android-app.yml",
})
TEMPORARY_ARTIFACT_PREFIX = "nori-release-"
MAX_DELETIONS = 400      # GitHub begrenzt schreibende Aufrufe; der Rest folgt beim nächsten Release
DELETE_DELAY = 1.0       # Sekunden zwischen zwei Löschungen


def parse_time(value: object) -> dt.datetime | None:
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


def keep_reason(run: dict, keep_run: int, started: dt.datetime, protected: set[str]) -> str | None:
    """Warum ein Lauf stehen bleibt — oder None, wenn er weg darf."""
    path = str(run.get("path", "")).split("@")[0]
    if path not in CLEANUP_WORKFLOWS:
        return "anderer Workflow"
    if run.get("id") == keep_run:
        return "dieser Lauf"
    if run.get("status") != "completed":
        return "noch nicht abgeschlossen"
    created = parse_time(run.get("created_at"))
    if created is None or created >= started:
        return "nach diesem Lauf gestartet"
    if path != RELEASE_WORKFLOW and run.get("head_sha") in protected:
        return "Prüflauf des veröffentlichten Stands oder eines offenen Pull Requests"
    return None


def cleanup(github, meta: Meta, platforms: list[str], keep_run: int, dry_run: bool = False,
            max_deletions: int = MAX_DELETIONS, delay: float = DELETE_DELAY) -> dict:
    """Alte Läufe der Nori-Build- und Release-Workflows löschen — erst nach geprüftem Release."""
    if not isinstance(keep_run, int) or keep_run <= 0:
        raise ReleaseError("Der laufende Lauf ist nicht bekannt (GITHUB_RUN_ID) – ohne ihn wird nichts gelöscht")
    validate_release(github, meta, platforms)
    current = github.run(keep_run)
    started = parse_time((current or {}).get("created_at"))
    if not current or current.get("id") != keep_run or started is None:
        raise ReleaseError(f"Lauf {keep_run} nicht gefunden – ohne ihn wird nichts gelöscht")
    protected = {meta.commit, *github.open_pull_heads()}

    candidates: list[dict] = []
    kept: dict[str, int] = {}
    for workflow in github.workflows():
        if workflow.get("path") not in CLEANUP_WORKFLOWS:
            continue
        for run in github.workflow_runs(workflow["id"]):
            reason = keep_reason(run, keep_run, started, protected)
            if reason:
                kept[reason] = kept.get(reason, 0) + 1
            else:
                candidates.append(run)
    candidates.sort(key=lambda run: (str(run.get("created_at")), run.get("id", 0)))

    deleted, stopped = 0, ""
    for run in candidates:
        if deleted >= max_deletions:
            stopped = f"Obergrenze von {max_deletions} Löschungen je Release erreicht"
            break
        if dry_run:
            print(f"würde löschen: Lauf {run['id']} {run.get('name')} ({run.get('head_branch')}, {run.get('created_at')})")
            deleted += 1
            continue
        try:
            github.delete_run(run["id"])
        except GitHubError as error:
            if error.status == 404:
                continue
            if error.rate_limited:
                stopped = f"GitHub bremst ({error})"
                break
            raise
        deleted += 1
        if delay:
            time.sleep(delay)

    removed = 0
    for artifact in github.artifacts(keep_run):
        if str(artifact.get("name", "")).startswith(TEMPORARY_ARTIFACT_PREFIX):
            if not dry_run:
                github.delete_artifact(artifact["id"])
            removed += 1

    left = len(candidates) - deleted
    verb = "würden gelöscht" if dry_run else "gelöscht"
    print(f"Läufe {verb}: {deleted}; bleiben stehen: " + (", ".join(f"{count} {reason}" for reason, count in sorted(kept.items())) or "keine"))
    print(f"Übergabe-Artefakte dieses Laufs {verb}: {removed}")
    if stopped:
        print(f"::warning::Aufräumen unterbrochen: {stopped}. {left} alte Läufe folgen beim nächsten Release.")
    write_summary([
        "## Aufräumen", "", f"- Läufe {verb}: {deleted}",
        *(f"- stehen geblieben ({reason}): {count}" for reason, count in sorted(kept.items())),
        f"- Übergabe-Artefakte dieses Laufs {verb}: {removed}",
        *([f"- unterbrochen: {stopped}; {left} folgen beim nächsten Release"] if stopped else []),
        "", "Releases, Anhänge, Tags und Branches bleiben unberührt.",
    ])
    return {"deleted": deleted, "kept": kept, "artifacts": removed, "left": left, "stopped": stopped}


# ── Kommandozeile ────────────────────────────────────────────────────────────


def write_outputs(values: dict[str, str], github_output: bool) -> None:
    target = os.environ.get("GITHUB_OUTPUT")
    if github_output and target:
        with open(target, "a", encoding="utf-8") as handle:
            for name, value in values.items():
                handle.write(f"{name}={value}\n")
    for name, value in values.items():
        print(f"{name}={value}")


def build_values(meta: Meta, platform: Platform, release: bool) -> dict[str, str]:
    suffix = "" if release else f"-{meta.commit[:7]}"
    values = {
        "version": meta.version, "tag": meta.tag, "title": meta.title, "commit": meta.commit,
        "release": "true" if release else "false", "suffix": suffix,
        "build": meta.builds.get(platform.key, ""),
        "artifact": f"{TEMPORARY_ARTIFACT_PREFIX}{platform.key}" if release else f"Nori-{platform.short}-v{meta.version}{suffix}",
        "retention": str(RELEASE_RETENTION_DAYS if release else TEST_RETENTION_DAYS),
    }
    for key in platform.assets:
        values[f"asset_{key.replace('-', '_')}"] = ASSETS[key].name(meta.version, suffix)
    if len(platform.assets) == 1:
        values["asset"] = ASSETS[platform.assets[0]].name(meta.version, suffix)
    return values


def command_meta(args) -> int:
    release = bool((args.release_version or "").strip())
    meta = read_meta(args.commit, args.release_version if release else None)
    write_outputs(build_values(meta, platform_for(args.platform), release), args.github_output)
    return 0


def command_prepare(args) -> int:
    meta, platforms = prepare(args.version, args.platforms, github_from_environment())
    values = {
        "version": meta.version, "tag": meta.tag, "title": meta.title, "commit": meta.commit,
        "platforms": ",".join(platforms),
        **{key: "true" if key in platforms else "false" for key in PLATFORMS},
        **{f"build_{key}": build for key, build in meta.builds.items()},
    }
    write_outputs(values, args.github_output)
    print(f"Bereit: {meta.title} aus {meta.commit[:7]} für {', '.join(PLATFORMS[key].display for key in platforms)}")
    write_summary([f"## {meta.title} vorbereitet", "", f"- Commit `{meta.commit[:7]}`",
                   f"- Plattformen: {', '.join(PLATFORMS[key].display for key in platforms)}",
                   *(f"- Build {key}: {build}" for key, build in meta.builds.items())])
    return 0


def command_source_package(args) -> int:
    commit = resolve_commit(args.commit)
    count = build_source_package(commit, args.output)
    print(f"Quellpaket {args.output.name}: {count} Dateien aus {commit[:7]}")
    return 0


def command_check_app(args) -> int:
    meta = read_meta(args.commit, args.release_version or None)
    check_app(args.platform, args.app, meta)
    print(f"{args.app.name}: {meta.version} ({meta.builds[args.platform]}), {meta.bundle_ids[args.platform]}")
    return 0


def command_verify(args) -> int:
    release = bool((args.release_version or "").strip())
    meta = read_meta(args.commit, args.release_version if release else None)
    spec = asset_for(args.asset)
    suffix = "" if release else f"-{meta.commit[:7]}"
    digest = verify_asset(meta, spec, args.file, args.sha256, suffix)
    if args.production:
        production_check(meta, spec, args.file)
    print(f"Paket geprüft: {args.file.name} passt zu Nori {meta.version} ({meta.commit[:7]})")
    write_outputs({"sha256": digest, f"sha256_{spec.key.replace('-', '_')}": digest}, args.github_output)
    return 0


def command_notes(args) -> int:
    meta = read_meta(args.commit, args.version)
    notes = build_notes(meta, parse_platforms(args.platforms), repository_name())
    if args.output:
        args.output.write_text(notes, encoding="utf-8")
    else:
        print(notes)
    return 0


def parse_checksum_args(values: list[str]) -> dict[str, str]:
    sums: dict[str, str] = {}
    for item in values or []:
        key, _, value = item.partition("=")
        asset_for(key)
        if not value.strip():
            continue
        sums[key] = normalize_sha256(value)
    return sums


def command_publish(args) -> int:
    require_main()
    commit = resolve_commit(args.commit)
    if resolve_commit("HEAD") != commit:
        raise ReleaseError(f"Ausgecheckt ist nicht der geprüfte Commit {commit[:7]}")
    meta = read_meta(commit, args.version)
    check_documents(meta)
    run_release(meta, parse_platforms(args.platforms), args.dir, github_from_environment(),
                parse_checksum_args(args.sha256), repository_name(), args.dry_run)
    return 0


def command_validate(args) -> int:
    meta = read_meta(args.commit, args.version)
    validate_release(github_from_environment(), meta, parse_platforms(args.platforms))
    return 0


def command_cleanup(args) -> int:
    require_main()
    current = os.environ.get("GITHUB_RUN_ID", "")
    if in_actions() and str(args.keep_run) != current:
        raise ReleaseError(f"--keep-run {args.keep_run} ist nicht dieser Lauf ({current or '?'}) – nichts wird gelöscht")
    meta = read_meta(args.commit, args.version)
    cleanup(github_from_environment(), meta, parse_platforms(args.platforms), args.keep_run,
            args.dry_run, args.max_deletions, args.delay)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    meta = commands.add_parser("meta", help="Version, Tag und Paketnamen einer Plattform")
    meta.add_argument("--platform", required=True, choices=list(PLATFORMS))
    meta.add_argument("--release-version", default="", help="leer: Testpaket mit Commit im Namen")
    meta.add_argument("--commit", default="HEAD")
    meta.add_argument("--github-output", action="store_true")
    meta.set_defaults(handler=command_meta)

    prep = commands.add_parser("prepare", help="vor dem Bauen: Version, Dokumente, Tags, Releases, Buildnummern")
    prep.add_argument("--version", required=True)
    prep.add_argument("--platforms", required=True)
    prep.add_argument("--github-output", action="store_true")
    prep.set_defaults(handler=command_prepare)

    source = commands.add_parser("source-package", help="macOS-Quellpaket aus dem Commit")
    source.add_argument("--output", type=Path, required=True)
    source.add_argument("--commit", default="HEAD")
    source.set_defaults(handler=command_source_package)

    app = commands.add_parser("check-app", help="gebautes Programm gegen Version und Build prüfen")
    app.add_argument("--platform", required=True, choices=list(XCODE_PROJECTS))
    app.add_argument("--app", type=Path, required=True)
    app.add_argument("--release-version", default="")
    app.add_argument("--commit", default="HEAD")
    app.set_defaults(handler=command_check_app)

    verify = commands.add_parser("verify", help="ein Paket gegen die Version des Commits prüfen")
    verify.add_argument("--asset", required=True, choices=list(ASSETS))
    verify.add_argument("--file", type=Path, required=True)
    verify.add_argument("--release-version", default="")
    verify.add_argument("--sha256")
    verify.add_argument("--commit", default="HEAD")
    verify.add_argument("--production", action="store_true", help="zusätzlich die Produktionsprüfung der Plattform")
    verify.add_argument("--github-output", action="store_true")
    verify.set_defaults(handler=command_verify)

    notes = commands.add_parser("notes", help="öffentliche Release Notes aus CHANGELOG.md")
    notes.add_argument("--version")
    notes.add_argument("--platforms", default=",".join(PLATFORMS))
    notes.add_argument("--commit", default="HEAD")
    notes.add_argument("--output", type=Path)
    notes.set_defaults(handler=command_notes)

    publish = commands.add_parser("publish", help="Release mit den geprüften Paketen dieses Laufs anlegen")
    publish.add_argument("--version", required=True)
    publish.add_argument("--platforms", required=True)
    publish.add_argument("--dir", type=Path, required=True)
    publish.add_argument("--sha256", action="append", default=[], metavar="PAKET=PRÜFSUMME")
    publish.add_argument("--commit", required=True)
    publish.add_argument("--dry-run", action="store_true")
    publish.set_defaults(handler=command_publish)

    validate = commands.add_parser("validate", help="veröffentlichten Release nachprüfen")
    validate.add_argument("--version", required=True)
    validate.add_argument("--platforms", required=True)
    validate.add_argument("--commit", required=True)
    validate.set_defaults(handler=command_validate)

    clean = commands.add_parser("cleanup", help="alte Läufe nach geprüftem Release löschen")
    clean.add_argument("--version", required=True)
    clean.add_argument("--platforms", required=True)
    clean.add_argument("--commit", required=True)
    clean.add_argument("--keep-run", type=int, required=True)
    clean.add_argument("--max-deletions", type=int, default=MAX_DELETIONS)
    clean.add_argument("--delay", type=float, default=DELETE_DELAY)
    clean.add_argument("--dry-run", action="store_true")
    clean.set_defaults(handler=command_cleanup)

    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except ReleaseError as error:
        prefix = "::error::" if in_actions() else "FEHLER "
        for line in str(error).splitlines():
            print(f"{prefix}{line}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
