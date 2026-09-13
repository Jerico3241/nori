#!/usr/bin/env python3
"""GitHub-Releases für Nori: eine Plattform, eine Version, genau ein geprüftes Paket.

Aufgerufen von `.github/workflows/release.yml`, und der wiederum nur als letzter
Job der Paket-Läufe auf `main` — `Package iOS IPA`, `Build webOS` und
`Package macOS Source`. Ein Release entsteht damit erst, wenn der Paket-Job mit
allen Produktions- und Zugangsdatenprüfungen grün war; ein roter oder
abgebrochener Paket-Job lässt den Release-Job gar nicht erst starten.

    python3 tools/nori-release.py meta     --platform ios
    python3 tools/nori-release.py verify   --platform webos --file apps/webos/tv.nori.app_2.2.1_all.ipk
    python3 tools/nori-release.py notes    --platform macos
    python3 tools/nori-release.py publish  --platform ios --dir <Artefakt> --sha256 <Prüfsumme> --commit <SHA>
    python3 tools/nori-release.py from-run --platform webos --run-id <ID> [--dry-run]

Die Regeln stehen hier und nirgends sonst:

* Tags heißen `ios-v<VERSION>`, `macos-v<VERSION>` und `webos-v<VERSION>`. Die
  Version kommt aus den Projektdateien des geprüften Commits, nie aus einem Tag.
* Eine Version bekommt höchstens einen Release. Gibt es ihn schon, endet der Lauf
  erfolgreich und ändert nichts. Ein Tag ohne Release, ein Tag auf einem anderen
  Commit oder ein liegengebliebener Entwurf brechen ab — verschoben,
  überschrieben oder gelöscht wird nie etwas.
* Veröffentlicht wird genau eine Datei: das Paket, das der Paket-Job geprüft und
  hochgeladen hat. Erkannt am Namen, an der Prüfsumme aus dem Paket-Job und am
  Inhalt — Version, Build, keine Zugangsdaten außer den vorgesehenen.
* Die Release Notes kommen aus `CHANGELOG.md`, ohne interne OAuth-, Secret- und
  Runner-Einzelheiten.

`from-run` holt einen Release für einen schon abgeschlossenen, erfolgreichen
Paket-Lauf nach — nur für den jüngsten auf `main` und nur für die Version, die
`main` gerade trägt.

Die GitHub-API wird über `urllib` angesprochen, nicht über die `gh`-CLI: der
Runner kommt ohne Homebrew aus (docs/self-hosted-runner.md). Das Token kommt aus
`GITHUB_TOKEN` oder `GH_TOKEN` und erscheint in keiner Ausgabe.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import os
import plistlib
import re
import ssl
import stat
import subprocess
import sys
import tempfile
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
BUILD_NUMBER = re.compile(r"^[1-9]\d*$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"^[0-9a-f]{40}$")


class ReleaseError(Exception):
    """Ein Grund, keinen Release anzulegen. Die Meldung ist fürs Protokoll gedacht."""


class GitHubError(ReleaseError):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status


# ── Plattformen ──────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Platform:
    key: str
    label: str            # Schreibweise im Titel und im Changelog: „iOS"
    display: str          # Anzeige in den Release Notes: „iOS/iPadOS"
    kind: str             # Paketart, bestimmt die Prüfung: ipa | ipk | source-zip
    asset: str            # Dateiname des Pakets
    artifact: str         # Name des Actions-Artefakts
    content_type: str
    workflow: str         # Paket-Lauf, der das Artefakt erzeugt
    required_steps: tuple[str, ...]  # müssen in diesem Lauf grün sein (from-run)
    hint: str

    @property
    def tag_prefix(self) -> str:
        return f"{self.key}-v"


# Soll macOS später ein `.app.zip` oder `.dmg` statt des Quellpakets
# veröffentlichen: `kind`, `asset`, `artifact` und `content_type` hier ändern und
# unter VERIFIERS eine Prüfung für die neue Paketart eintragen.
PLATFORMS = {
    "ios": Platform(
        key="ios",
        label="iOS",
        display="iOS/iPadOS",
        kind="ipa",
        asset="Nori-iOS-{version}-unsigned.ipa",
        artifact="Nori-iOS-{version}-unsigned",
        content_type="application/octet-stream",
        workflow=".github/workflows/package-ios-ipa.yml",
        required_steps=(
            "Google OAuth im gebauten Programm prüfen",
            "Google OAuth in der fertigen IPA prüfen",
            "IPA hochladen",
            "Lokale Google-Konfiguration entfernen",
        ),
        hint="Unsigned IPA – muss vor der Installation mit einer gültigen Signatur signiert werden.",
    ),
    "macos": Platform(
        key="macos",
        label="macOS",
        display="macOS",
        kind="source-zip",
        asset="Nori-macOS-{version}-source.zip",
        artifact="Nori-macOS-{version}-source",
        content_type="application/zip",
        workflow=".github/workflows/package-macos-source.yml",
        required_steps=("Create macOS source package", "Upload package"),
        hint="Quellpaket – in Xcode öffnen und mit einem eigenen Team signieren; ein fertiges Programm liegt nicht bei.",
    ),
    "webos": Platform(
        key="webos",
        label="webOS",
        display="LG webOS",
        kind="ipk",
        asset="tv.nori.app_{version}_all.ipk",
        artifact="Nori-webOS",
        content_type="application/octet-stream",
        workflow=".github/workflows/build-webos.yml",
        required_steps=(
            "Fernbedienung durchspielen",
            "Google-TV-OAuth bereitstellen",
            "Paket prüfen",
            "Paket als Artefakt ablegen",
            "Zugangsdaten aus dem Checkout entfernen",
        ),
        hint="Installationspaket für LG webOS.",
    ),
}

XCODE_PROJECTS = {
    "ios": "native/Nori-iOS/Nori.xcodeproj/project.pbxproj",
    "macos": "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj",
}
WEBOS_APPINFO = "apps/webos/appinfo.json"

# Inhalt des macOS-Quellpakets — dieselbe Liste wie in package-macos-source.yml.
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
}


def platform_for(key: str) -> Platform:
    try:
        return PLATFORMS[key]
    except KeyError:
        raise ReleaseError(f"Unbekannte Plattform {key!r} – erwartet {', '.join(sorted(PLATFORMS))}") from None


# ── Version aus dem Commit ───────────────────────────────────────────────────


@dataclass(frozen=True)
class Meta:
    platform: Platform
    version: str
    build: str | None
    bundle_id: str
    commit: str

    @property
    def tag(self) -> str:
        return f"{self.platform.tag_prefix}{self.version}"

    @property
    def title(self) -> str:
        return f"Nori {self.platform.label} {self.version}"

    @property
    def asset(self) -> str:
        return self.platform.asset.format(version=self.version)

    @property
    def artifact(self) -> str:
        return self.platform.artifact.format(version=self.version)


def git(*args: str) -> str:
    result = subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise ReleaseError(f"git {args[0]} fehlgeschlagen: {result.stderr.strip()[:300]}")
    return result.stdout


def resolve_commit(ref: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(ROOT), "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        capture_output=True, text=True,
    )
    sha = result.stdout.strip()
    if result.returncode != 0 or not COMMIT.match(sha):
        raise ReleaseError(f"Commit {ref!r} ist nicht vorhanden")
    return sha


def file_at(commit: str, path: str) -> str:
    return git("show", f"{commit}:{path}")


def validate_version(version: object, origin: str) -> str:
    if not isinstance(version, str) or not SEMVER.match(version):
        raise ReleaseError(f"Ungültige Versionsnummer {version!r} in {origin} – erwartet x.y.z")
    return version


def single_setting(project: str, name: str, origin: str) -> str:
    values = {value.strip().strip('"') for value in re.findall(rf"\b{name} = ([^;]*);", project)}
    if not values:
        raise ReleaseError(f"{name} fehlt in {origin}")
    if len(values) > 1:
        raise ReleaseError(f"{name} ist in {origin} uneinheitlich: {', '.join(sorted(values))}")
    return values.pop()


def read_meta(key: str, ref: str = "HEAD") -> Meta:
    """Version, Build und Kennung so, wie sie im Commit stehen."""
    platform = platform_for(key)
    commit = resolve_commit(ref)
    if platform.key == "webos":
        try:
            info = json.loads(file_at(commit, WEBOS_APPINFO))
        except json.JSONDecodeError:
            raise ReleaseError(f"{WEBOS_APPINFO} ist kein gültiges JSON") from None
        version = validate_version(info.get("version"), WEBOS_APPINFO)
        return Meta(platform, version, None, str(info.get("id", "")), commit)

    origin = XCODE_PROJECTS[platform.key]
    project = file_at(commit, origin)
    version = validate_version(single_setting(project, "MARKETING_VERSION", origin), origin)
    build = single_setting(project, "CURRENT_PROJECT_VERSION", origin)
    if not BUILD_NUMBER.match(build):
        raise ReleaseError(f"Ungültige Buildnummer {build!r} in {origin}")
    bundle_id = single_setting(project, "PRODUCT_BUNDLE_IDENTIFIER", origin)
    return Meta(platform, version, build, bundle_id, commit)


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


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

VERIFIERS = {"ipa": "verify_ipa", "ipk": "verify_ipk", "source-zip": "verify_source_zip"}


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


def find_asset(directory: Path, meta: Meta) -> Path:
    """Das Artefakt enthält genau eine Datei — sonst ist es das falsche."""
    if not directory.is_dir():
        raise ReleaseError(f"Artefakt {meta.artifact} fehlt")
    entries = sorted(path for path in directory.rglob("*") if not path.is_dir())
    if len(entries) != 1:
        names = ", ".join(path.name for path in entries[:5]) or "nichts"
        raise ReleaseError(f"Artefakt {meta.artifact} soll genau eine Datei enthalten, enthält {len(entries)}: {names}")
    return entries[0]


def verify_asset(meta: Meta, path: Path, expected_sha256: str | None = None) -> str:
    """Name, Prüfsumme und Inhalt des Pakets gegen die Version des Commits."""
    if path.is_symlink() or not path.is_file():
        raise ReleaseError(f"{path.name} ist keine reguläre Datei")
    if path.name != meta.asset:
        raise ReleaseError(f"Falsches Paket: {path.name} – für {meta.tag} erwartet {meta.asset}")
    digest = sha256_file(path)
    if expected_sha256 is not None:
        expected = normalize_sha256(expected_sha256)
        if digest != expected:
            raise ReleaseError(
                f"{path.name}: Prüfsumme {digest[:12]}… weicht vom geprüften Paket ab ({expected[:12]}…)"
            )
    globals()[VERIFIERS[meta.platform.kind]](meta, path)
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
        raise ReleaseError(f"{label}: {what} ist {actual!r}, der Tag verlangt {expected!r}")


def scan_contents(label: str, files: Iterable[tuple[str, bytes]], kind: str, patterns: bool) -> None:
    """Keine Tokens, Cookies oder fremden Zugangsdaten im Inhalt."""
    allowed = ALLOWED_CREDENTIALS[kind]
    known = {origin: value.encode() for origin, value in known_credentials().items() if origin not in allowed}
    for name, data in files:
        if patterns:
            for pattern, what in TOKEN_PATTERNS:
                if pattern.search(data):
                    raise ReleaseError(f"{label}: {what} in {name}")
            # Das TV-Paket trägt genau ein Secret; welches, prüft check-webos-package.py --production.
            if kind != "ipk" and CLIENT_SECRET_ANY.search(data):
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
        expect_equal(label, "Build (CFBundleVersion)", info.get("CFBundleVersion"), meta.build)
        expect_equal(label, "Bundle-ID", info.get("CFBundleIdentifier"), meta.bundle_id)
        files = ((entry.filename, archive.read(entry)) for entry in infos if not entry.is_dir())
        scan_contents(label, files, "ipa", patterns=True)


def webos_checker():
    spec = importlib.util.spec_from_file_location("check_webos_package", TOOLS / "check-webos-package.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
    expect_equal(label, "Paketname (control)", fields.get("Package"), meta.bundle_id)
    expect_equal(label, "Version (control)", fields.get("Version"), meta.version)

    appinfo_path = f"usr/palm/applications/{meta.bundle_id}/appinfo.json"
    try:
        appinfo = json.loads(by_name[appinfo_path])
    except KeyError:
        raise ReleaseError(f"{label}: {appinfo_path} fehlt") from None
    except ValueError:
        raise ReleaseError(f"{label}: appinfo.json ist kein gültiges JSON") from None
    expect_equal(label, "Version (appinfo.json)", appinfo.get("version"), meta.version)
    expect_equal(label, "App-ID (appinfo.json)", appinfo.get("id"), meta.bundle_id)
    scan_contents(label, files, "ipk", patterns=True)


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

    tree: dict[str, tuple[str, str]] = {}
    listing = git("ls-tree", "-r", "-z", "--full-tree", meta.commit, "--", *SOURCE_PATHS[meta.platform.key])
    for record in listing.split("\0"):
        if not record:
            continue
        header, _, name = record.partition("\t")
        mode, kind, sha = header.split()
        if kind == "blob":
            tree[name] = (mode, sha)
    if not tree:
        raise ReleaseError(f"{label}: Commit {meta.commit[:7]} enthält keine Quelldateien")

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

    project = XCODE_PROJECTS[meta.platform.key]
    version = single_setting(entries[project][0].decode("utf-8", "replace"), "MARKETING_VERSION", project)
    expect_equal(label, "MARKETING_VERSION", version, meta.version)
    # Kein Musterabgleich: die Tests im Quellpaket tragen absichtlich erfundene Tokens.
    scan_contents(label, ((name, data) for name, (data, _) in entries.items()), "source-zip", patterns=False)


def production_check(meta: Meta, path: Path) -> None:
    """Die Produktionsprüfung des Paket-Laufs noch einmal — gegen genau diese Datei."""
    kind = meta.platform.kind
    if kind == "ipa":
        command = [sys.executable, str(ROOT / "tools/configure-google-oauth.py"), "--verify-ios-ipa", str(path)]
    elif kind == "ipk":
        command = [sys.executable, str(ROOT / "tools/check-webos-package.py"), "--production", "--ipk", str(path)]
    else:
        return  # verify_source_zip hat jede Datei mit dem Commit verglichen
    # CI=true: die Werkzeuge kürzen Client-IDs dann auch außerhalb der CI.
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, env={**os.environ, "CI": "true"})
    lines = [line for line in result.stdout.splitlines() if line.strip() and not line.startswith("WARN")]
    for line in lines[-8:]:
        print(f"  {line}")
    if result.returncode != 0:
        raise ReleaseError(f"Produktionsprüfung für {path.name} fehlgeschlagen – kein Release")


# ── Release Notes ────────────────────────────────────────────────────────────

# Was in öffentliche Notes nicht gehört. Ein Satz oder Punkt, der eines davon
# nennt, fällt heraus — bei Punkten mit fetter Überschrift bleibt die Überschrift.
SENSITIVE = re.compile(
    r"secret|client[-_ ]?id|oauth|\.env\b|xcconfig|\.config/|token|VITE_|GOOGLE_CLIENT|GoogleClient"
    r"|device[-_ ]?code|user[-_ ]?code|cookie|googleusercontent|GOCSPX|zugangsdaten|credential|runner",
    re.IGNORECASE,
)
PUBLIC_SECTIONS = {
    "Behoben", "Geändert", "Geaendert", "Hinzugefügt", "Hinzugefuegt", "Neu", "Entfernt",
    "Verbessert", "Sicherheit", "Bekannte Einschränkungen", "Hinweis zum Update",
}
PLATFORM_WORDS = {
    "ios": (r"\biOS\b", r"\biPadOS\b", r"\biPhone\b", r"\biPad\b"),
    "macos": (r"\bmacOS\b", r"\bMac\b"),
    "webos": (r"\bwebOS\b", r"\bTV\b", r"\bFernseher\b"),
}
BULLET = re.compile(r"^[-*] ")
SUB_BULLET = re.compile(r"^\s+[-*] ")
ABBREVIATION = re.compile(r"(?:\b(?:z|B|d|h|u|a|bzw|ca|inkl|vgl|Nr|evtl|ggf|usw|etc|max|min|Std|Sek|Min)|\d)\.$")


def changelog_tool():
    spec = importlib.util.spec_from_file_location("changelog_section", TOOLS / "changelog-section.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def section_applies(heading: str, key: str) -> bool:
    """`### Behoben — macOS` gehört nicht in die iOS-Notes; `### Tests` in keine."""
    parts = re.split(r"\s+[—–]\s+", heading.lstrip("#").strip(), maxsplit=1)
    base, scope = parts[0].strip(), (parts[1].strip() if len(parts) > 1 else "")
    if base not in PUBLIC_SECTIONS:
        return False
    mentioned = {name for name, words in PLATFORM_WORDS.items() if any(re.search(word, scope) for word in words)}
    if re.search(r"\bApple\b", scope):
        mentioned |= {"ios", "macos"}
    return not mentioned or key in mentioned


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


def public_changes(section: str, key: str) -> str:
    """Die für diese Plattform öffentlichen Teile eines Changelog-Abschnitts."""
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
            include = section_applies(line, key)
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


def build_notes(meta: Meta, repository: str) -> str:
    changelog = file_at(meta.commit, "CHANGELOG.md")
    section = changelog_tool().extract(changelog, meta.platform.label, meta.version)
    if section is None:
        raise ReleaseError(
            f"CHANGELOG.md hat in {meta.commit[:7]} keinen Abschnitt [{meta.platform.label} {meta.version}] – kein Release"
        )
    changes = public_changes(section, meta.platform.key) or (
        "Keine gesonderten Hinweise für diese Plattform; Einzelheiten stehen in `CHANGELOG.md`."
    )
    facts = [f"- **Plattform:** {meta.platform.display}", f"- **Version:** {meta.version}"]
    if meta.build:
        facts.append(f"- **Build:** {meta.build}")
    facts.append(f"- **Commit:** [`{meta.commit[:7]}`](https://github.com/{repository}/commit/{meta.commit})")
    notes = "\n".join([
        *facts, "", f"> {meta.platform.hint}", "", "## Änderungen", "", changes, "", "---", "",
        f"Paket: `{meta.asset}`", "",
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


class GitHub:
    """Die wenigen REST-Aufrufe, die ein Release braucht."""

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
        if not url.startswith("http"):
            url = f"{self.api}/repos/{self.repository}{url}"
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
            path = urllib.parse.urlsplit(url).path
            raise GitHubError(error.code, f"GitHub {method} {path}: HTTP {error.code} {detail[:200]}".rstrip()) from None
        except urllib.error.URLError as error:
            raise GitHubError(0, f"GitHub {method} nicht erreichbar: {error.reason}") from None
        if raw:
            return content
        return json.loads(content) if content else None

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

    def tags(self, prefix: str) -> list[str]:
        refs = self.request("GET", f"/git/matching-refs/tags/{urllib.parse.quote(prefix)}") or []
        return [item["ref"].removeprefix("refs/tags/") for item in refs]

    def releases(self) -> list[dict]:
        found: list[dict] = []
        for page in range(1, 51):
            batch = self.request("GET", f"/releases?per_page=100&page={page}") or []
            found.extend(batch)
            if len(batch) < 100:
                break
        return found

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
        return self.request("GET", f"/releases/{release['id']}/assets?per_page=100") or []

    def download_asset(self, asset: dict) -> bytes:
        return self.request("GET", f"/releases/assets/{asset['id']}", accept="application/octet-stream", raw=True)

    def create_tag(self, tag: str, commit: str, message: str) -> None:
        tag_object = self.request("POST", "/git/tags", {"tag": tag, "message": message, "object": commit, "type": "commit"})
        # Legt die Referenz an; gibt es sie schon, antwortet GitHub mit 422 — verschoben wird nichts.
        self.request("POST", "/git/refs", {"ref": f"refs/tags/{tag}", "sha": tag_object["sha"]})

    def publish(self, release: dict) -> dict:
        return self.request("PATCH", f"/releases/{release['id']}", {"draft": False})

    def release_by_tag(self, tag: str) -> dict | None:
        return self.request("GET", f"/releases/tags/{urllib.parse.quote(tag)}", missing_ok=True)

    def run(self, run_id: str) -> dict:
        return self.request("GET", f"/actions/runs/{run_id}")

    def jobs(self, run_id: str) -> list[dict]:
        return (self.request("GET", f"/actions/runs/{run_id}/jobs?per_page=100") or {}).get("jobs", [])

    def latest_successful_run(self, workflow: str) -> dict | None:
        name = urllib.parse.quote(Path(workflow).name)
        runs = self.request("GET", f"/actions/workflows/{name}/runs?branch=main&status=success&per_page=1") or {}
        return next(iter(runs.get("workflow_runs", [])), None)

    def artifacts(self, run_id: str) -> list[dict]:
        return (self.request("GET", f"/actions/runs/{run_id}/artifacts?per_page=100") or {}).get("artifacts", [])

    def download_artifact(self, artifact: dict, destination: Path) -> None:
        content = self.request("GET", f"/actions/artifacts/{artifact['id']}/zip", raw=True)
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            for info in archive.infolist():
                safe_member(info.filename, f"Artefakt {artifact.get('name')}")
            archive.extractall(destination)


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


# ── Entscheiden und veröffentlichen ──────────────────────────────────────────


@dataclass(frozen=True)
class Decision:
    action: str  # create | skip
    reason: str


def decide(meta: Meta, tag_commit: str | None, releases: list[dict], tags: list[str]) -> Decision:
    """Neu anlegen, erfolgreich überspringen oder abbrechen — nie verschieben."""
    same = [release for release in releases if release.get("tag_name") == meta.tag]
    if any(not release.get("draft") for release in same):
        moved = "" if tag_commit in (None, meta.commit) else f" (Tag auf {tag_commit[:7]}, dieser Lauf {meta.commit[:7]})"
        return Decision("skip", f"Release {meta.tag} existiert bereits{moved} – kein zweiter Release, der Tag bleibt, wo er ist.")
    if same:
        raise ReleaseError(
            f"Für {meta.tag} liegt ein unveröffentlichter Entwurf – er wird weder überschrieben noch gelöscht. Bitte von Hand prüfen."
        )
    if tag_commit is not None:
        if tag_commit != meta.commit:
            raise ReleaseError(
                f"Tag {meta.tag} zeigt auf {tag_commit[:7]}, geprüft wurde {meta.commit[:7]} – der Tag wird nicht verschoben, kein Release."
            )
        raise ReleaseError(f"Tag {meta.tag} existiert ohne Release – kein neuer Release, der Tag bleibt unangetastet. Bitte von Hand prüfen.")

    prefix = meta.platform.tag_prefix
    names = {*tags, *(str(release.get("tag_name") or "") for release in releases)}
    newer = sorted(
        (name for name in names
         if name.startswith(prefix) and SEMVER.match(name[len(prefix):])
         and version_key(name[len(prefix):]) > version_key(meta.version)),
        key=lambda name: version_key(name[len(prefix):]),
    )
    if newer:
        raise ReleaseError(f"{meta.tag} ist älter als das vorhandene {newer[-1]} – kein Release.")
    return Decision("create", f"{meta.tag} ist neu – Release wird angelegt.")


def check_uploaded(github, release: dict, meta: Meta, asset: Path, digest: str) -> None:
    assets = github.assets(release)
    if [item.get("name") for item in assets] != [meta.asset]:
        raise ReleaseError(f"Entwurf {meta.tag} trägt unerwartete Anhänge – wird nicht veröffentlicht")
    uploaded = assets[0]
    if uploaded.get("state") != "uploaded" or uploaded.get("size") != asset.stat().st_size:
        raise ReleaseError(f"Anhang {meta.asset} ist unvollständig hochgeladen – Entwurf wird nicht veröffentlicht")
    remote = uploaded.get("digest")
    matches = (remote == f"sha256:{digest}") if remote else (hashlib.sha256(github.download_asset(uploaded)).hexdigest() == digest)
    if not matches:
        raise ReleaseError(f"Hochgeladener Anhang {meta.asset} weicht vom geprüften Paket ab – Entwurf wird nicht veröffentlicht")


def run_release(meta: Meta, locate: Callable[[], Path], github, expected_sha256: str | None,
                repository: str, dry_run: bool = False) -> str:
    decision = decide(meta, github.tag_commit(meta.tag), github.releases(), github.tags(meta.platform.tag_prefix))
    print(decision.reason)
    if decision.action == "skip":
        return "skip"

    asset = locate()
    digest = verify_asset(meta, asset, expected_sha256)
    print(f"Paket geprüft: {asset.name} ({asset.stat().st_size} Bytes, sha256 {digest})")
    production_check(meta, asset)
    notes = build_notes(meta, repository)
    if not github.on_main(meta.commit):
        raise ReleaseError(f"Commit {meta.commit[:7]} liegt nicht auf main – kein Release.")
    if dry_run:
        print(f"Probelauf: {meta.title} würde mit {asset.name} auf {meta.commit[:7]} angelegt. Release Notes:\n")
        print(notes)
        return "dry-run"

    # Erst ein unsichtbarer Entwurf mit geprüftem Anhang, dann der Tag, dann die
    # Veröffentlichung. Scheitert ein Schritt, bleibt nichts Halbes öffentlich
    # stehen, und der nächste Lauf bricht mit einer klaren Meldung ab.
    draft = github.create_draft(meta, notes)
    github.upload(draft, asset, meta.asset, meta.platform.content_type)
    check_uploaded(github, draft, meta, asset, digest)
    message = meta.title + (f" ({meta.build})" if meta.build else "")
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
    if [item.get("name") for item in final.get("assets", [])] != [meta.asset]:
        raise ReleaseError(f"Release {meta.tag} trägt unerwartete Anhänge")
    print(f"Release angelegt: {meta.title} – {final.get('html_url', '')}")
    return "created"


def check_run(platform: Platform, run: dict, jobs: list[dict]) -> None:
    """Nur ein erfolgreicher Paket-Lauf auf main, dessen Prüfschritte alle grün waren."""
    run_id = run.get("id")
    path = str(run.get("path", "")).split("@")[0]
    if path != platform.workflow:
        raise ReleaseError(f"Lauf {run_id} stammt aus {path or '?'}, erwartet {platform.workflow}")
    if run.get("head_branch") != "main":
        raise ReleaseError(f"Lauf {run_id} lief auf {run.get('head_branch')!r}, nicht auf main – kein Release.")
    if run.get("event") not in ("push", "workflow_dispatch"):
        raise ReleaseError(f"Lauf {run_id} wurde durch {run.get('event')!r} ausgelöst – kein Release.")
    if run.get("status") != "completed" or run.get("conclusion") != "success":
        raise ReleaseError(
            f"Lauf {run_id} ist nicht erfolgreich abgeschlossen ({run.get('status')}/{run.get('conclusion')}) – kein Release."
        )
    failed = [job.get("name") for job in jobs if job.get("conclusion") not in ("success", "skipped")]
    if failed:
        raise ReleaseError(f"Lauf {run_id}: Job {failed[0]} nicht erfolgreich – kein Release.")
    steps = {step.get("name"): step.get("conclusion") for job in jobs for step in job.get("steps", [])}
    for required in platform.required_steps:
        if steps.get(required) != "success":
            raise ReleaseError(
                f"Lauf {run_id}: Schritt „{required}“ nicht erfolgreich ({steps.get(required) or 'fehlt'}) – kein Release."
            )


def ensure_commit(commit: str) -> None:
    if not COMMIT.match(commit or ""):
        raise ReleaseError("Lauf ohne gültigen Commit")
    probe = subprocess.run(["git", "-C", str(ROOT), "cat-file", "-e", f"{commit}^{{commit}}"], capture_output=True)
    if probe.returncode != 0:
        git("fetch", "--quiet", "origin", commit)


def release_from_run(key: str, run_id: str, github, repository: str, dry_run: bool = False) -> str:
    platform = platform_for(key)
    if not re.fullmatch(r"[1-9]\d*", str(run_id)):
        raise ReleaseError(f"Ungültige Lauf-ID {run_id!r}")
    run = github.run(run_id)
    check_run(platform, run, github.jobs(run_id))
    latest = github.latest_successful_run(platform.workflow)
    if not latest or latest.get("id") != run.get("id"):
        raise ReleaseError(
            f"Lauf {run_id} ist nicht der jüngste erfolgreiche Lauf von {platform.workflow} auf main "
            f"({(latest or {}).get('id', 'keiner')}) – keine alten Artefakte."
        )
    commit = str(run.get("head_sha", ""))
    ensure_commit(commit)
    meta = read_meta(key, commit)
    current = read_meta(key, "HEAD")
    # Die Produktionsprüfung läuft mit den Werkzeugen und dem Quelltext von
    # HEAD; sie gilt nur, wenn HEAD dieselbe Fassung trägt.
    if (current.version, current.build) != (meta.version, meta.build):
        raise ReleaseError(
            f"Lauf {run_id} baute {meta.version}, der ausgecheckte Stand trägt {current.version} – kein Release für einen anderen Stand."
        )
    print(f"Lauf {run_id}: {platform.workflow} auf main, {commit[:7]}, erfolgreich, Prüfschritte grün.")

    with tempfile.TemporaryDirectory(prefix="nori-release-") as temp:
        destination = Path(temp)

        def locate() -> Path:
            matching = [item for item in github.artifacts(run_id) if item.get("name") == meta.artifact]
            if len(matching) != 1:
                raise ReleaseError(f"Lauf {run_id} hat kein eindeutiges Artefakt {meta.artifact}")
            if matching[0].get("expired"):
                raise ReleaseError(f"Artefakt {meta.artifact} aus Lauf {run_id} ist abgelaufen")
            github.download_artifact(matching[0], destination)
            return find_asset(destination, meta)

        return run_release(meta, locate, github, None, repository, dry_run)


# ── Kommandozeile ────────────────────────────────────────────────────────────


def write_outputs(values: dict[str, str], github_output: bool) -> None:
    target = os.environ.get("GITHUB_OUTPUT")
    if github_output and target:
        with open(target, "a", encoding="utf-8") as handle:
            for name, value in values.items():
                handle.write(f"{name}={value}\n")
    for name, value in values.items():
        print(f"{name}={value}")


def command_meta(args) -> int:
    meta = read_meta(args.platform, args.commit)
    write_outputs({
        "version": meta.version, "build": meta.build or "", "tag": meta.tag, "title": meta.title,
        "asset": meta.asset, "artifact": meta.artifact, "commit": meta.commit,
    }, args.github_output)
    return 0


def command_verify(args) -> int:
    meta = read_meta(args.platform, args.commit)
    asset = args.file if args.file else find_asset(args.dir, meta)
    digest = verify_asset(meta, asset, args.sha256)
    if args.production:
        production_check(meta, asset)
    print(f"Paket geprüft: {asset.name} passt zu {meta.tag} ({meta.commit[:7]})")
    write_outputs({"asset": asset.name, "sha256": digest}, args.github_output)
    return 0


def command_notes(args) -> int:
    notes = build_notes(read_meta(args.platform, args.commit), repository_name())
    if args.output:
        args.output.write_text(notes, encoding="utf-8")
    else:
        print(notes)
    return 0


def command_publish(args) -> int:
    expected = normalize_sha256(args.sha256)
    if os.environ.get("GITHUB_ACTIONS") and os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise ReleaseError("Releases entstehen nur auf main")
    commit = resolve_commit(args.commit)
    if resolve_commit("HEAD") != commit:
        raise ReleaseError(f"Ausgecheckt ist nicht der geprüfte Commit {commit[:7]}")
    meta = read_meta(args.platform, commit)
    run_release(meta, lambda: find_asset(args.dir, meta), github_from_environment(), expected,
                repository_name(), args.dry_run)
    return 0


def command_from_run(args) -> int:
    release_from_run(args.platform, args.run_id, github_from_environment(), repository_name(), args.dry_run)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    def add(name: str, handler, help_text: str):
        sub = commands.add_parser(name, help=help_text)
        sub.add_argument("--platform", required=True, choices=sorted(PLATFORMS))
        sub.set_defaults(handler=handler)
        return sub

    meta = add("meta", command_meta, "Version, Tag und Paketname aus dem Commit")
    meta.add_argument("--commit", default="HEAD")
    meta.add_argument("--github-output", action="store_true")

    verify = add("verify", command_verify, "Paket gegen die Version des Commits prüfen")
    source = verify.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", type=Path)
    source.add_argument("--dir", type=Path)
    verify.add_argument("--sha256")
    verify.add_argument("--commit", default="HEAD")
    verify.add_argument("--production", action="store_true", help="zusätzlich die Produktionsprüfung der Plattform")
    verify.add_argument("--github-output", action="store_true")

    notes = add("notes", command_notes, "öffentliche Release Notes aus CHANGELOG.md")
    notes.add_argument("--commit", default="HEAD")
    notes.add_argument("--output", type=Path)

    publish = add("publish", command_publish, "Release für das geprüfte Paket dieses Laufs anlegen")
    publish.add_argument("--dir", type=Path, required=True)
    publish.add_argument("--sha256", required=True)
    publish.add_argument("--commit", required=True)
    publish.add_argument("--dry-run", action="store_true")

    from_run = add("from-run", command_from_run, "Release für einen abgeschlossenen Paket-Lauf nachholen")
    from_run.add_argument("--run-id", required=True)
    from_run.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except ReleaseError as error:
        prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") else "FEHLER "
        print(f"{prefix}{error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
