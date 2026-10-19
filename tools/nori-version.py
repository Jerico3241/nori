#!/usr/bin/env python3
"""Die Versionsnummer der Nori-App für iPhone und iPad.

Seit Nori 2.6.0 gibt es eine gemeinsame Nummer. Seit macOS, Windows und
LG webOS entfernt sind, steht sie nur noch in `MARKETING_VERSION` des
iOS-Projekts. Welche Stellen das sind, steht hier und nirgends sonst.

    python3 tools/nori-version.py show
    python3 tools/nori-version.py check [--version 2.6.0] [--against origin/main]
    python3 tools/nori-version.py set 2.6.0
    python3 tools/nori-version.py bump patch|minor|major

Neben der Nummer bleibt die Buildnummer: `CURRENT_PROJECT_VERSION` wird zu
`CFBundleVersion`. `set` und `bump` erhöhen sie um eins — ein neuer Stand muss vom System als
neuer erkannt werden, auch wenn jemand dieselbe Nummer zweimal baut.

`check` prüft:

* alle Stellen tragen dieselbe Nummer im Format `x.y.z`,
* die Buildnummer ist eine ganze Zahl ab 1, im Projekt einheitlich,
* `CHANGELOG.md` hat einen Abschnitt `## [Nori x.y.z]` und nennt in der
  Übersicht `Nori **x.y.z**`, `README.md` ebenso — in der Zeile für iOS,
* mit `--against <ref>`: Hat sich seit `<ref>` etwas geändert, das in einem
  Paket landet, muss die Nummer **größer** sein als jede Nummer in `<ref>`,
  und die Buildnummer muss steigen. Zwei verschiedene Pakete unter
  derselben Nummer lassen sich hinterher nicht mehr auseinanderhalten — und
  ein Gerät installiert das zweite nicht über das erste.

Ohne `--commit` wird die Arbeitskopie gelesen, mit `--commit` der Stand eines
Commits. Geschrieben wird nur die Arbeitskopie.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent

SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
BUILD_NUMBER = re.compile(r"^[1-9]\d*$")

CHANGELOG = "CHANGELOG.md"
README = "README.md"

# Die Zeilen der Übersicht in README.md, die die Nummer tragen müssen.
README_ROWS = ("iOS / iPadOS",)

# Was in einem installierbaren Paket landet. Tests, Dokumentation und
# Prüfskripte ändern kein Paket und verlangen deshalb keine neue Nummer.
PACKAGE_PATHS = (
    "native/NoriCore/Sources",
    "native/Nori-iOS",
    "native/Nori-Android",
    "native/Package.swift",
    "config/contract.json",
    ":(exclude)native/Nori-iOS/README.md",
)


class VersionError(Exception):
    """Eine Stelle trägt die falsche Nummer. Die Meldung ist fürs Protokoll gedacht."""


def is_version(value: object) -> bool:
    return isinstance(value, str) and bool(SEMVER.match(value))


def version_key(version: str) -> tuple[int, int, int]:
    major, minor, patch = (int(part) for part in version.split("."))
    return major, minor, patch


def normalize_version(value: str | None) -> str:
    """`2.6.0`, `v2.6.0` und ` V2.6.0 ` sind dieselbe Eingabe; alles andere nicht."""
    text = (value or "").strip()
    if text[:1] in ("v", "V"):
        text = text[1:]
    if not SEMVER.match(text):
        raise VersionError(
            f"Ungültige Version {value!r} – erwartet x.y.z (z. B. 2.6.0 oder v2.6.0), ohne führende Nullen und ohne Zusatz"
        )
    return text


def next_version(version: str, part: str) -> str:
    major, minor, patch = version_key(version)
    if part == "major":
        return f"{major + 1}.0.0"
    if part == "minor":
        return f"{major}.{minor + 1}.0"
    if part == "patch":
        return f"{major}.{minor}.{patch + 1}"
    raise VersionError(f"Unbekannter Teil {part!r} – erwartet major, minor oder patch")


# ── Wo die Nummer steht ──────────────────────────────────────────────────────


@dataclass(frozen=True)
class Location:
    path: str
    label: str


LOCATIONS = (
    Location("native/Nori-iOS/Nori.xcodeproj/project.pbxproj", "iOS/iPadOS – MARKETING_VERSION"),
)

# Buildnummer (CFBundleVersion) und Kennung.
XCODE_PROJECTS = {
    "ios": "native/Nori-iOS/Nori.xcodeproj/project.pbxproj",
}

def settings(text: str, name: str) -> list[str]:
    return [value.strip().strip('"') for value in re.findall(rf"\b{name} = ([^;]*);", text)]


def single_setting(text: str, name: str, origin: str) -> str:
    values = set(settings(text, name))
    if not values:
        raise VersionError(f"{name} fehlt in {origin}")
    if len(values) > 1:
        raise VersionError(f"{name} ist in {origin} uneinheitlich: {', '.join(sorted(values))}")
    return values.pop()


def read_location(location: Location, text: str) -> dict[str, object]:
    """Alle Nummern, die an dieser Stelle stehen — benannt, damit eine Abweichung zu finden ist."""
    values = settings(text, "MARKETING_VERSION")
    if not values:
        raise VersionError(f"MARKETING_VERSION fehlt in {location.path}")
    return {f"MARKETING_VERSION #{index + 1}": value for index, value in enumerate(values)}


# ── Lesen ────────────────────────────────────────────────────────────────────


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True)


def reader(commit: str | None) -> Callable[[str], str]:
    """Liest eine Datei aus der Arbeitskopie oder aus einem Commit."""
    if commit is None:
        def from_worktree(path: str) -> str:
            try:
                return (ROOT / path).read_text(encoding="utf-8")
            except FileNotFoundError:
                raise VersionError(f"{path} fehlt") from None
        return from_worktree

    def from_commit(path: str) -> str:
        result = git("show", f"{commit}:{path}")
        if result.returncode != 0:
            raise VersionError(f"{path} fehlt in {commit}")
        return result.stdout
    return from_commit


@dataclass(frozen=True)
class State:
    values: dict[str, object]       # „Stelle: Feld" → Nummer
    builds: dict[str, str]          # ios → CURRENT_PROJECT_VERSION
    bundle_ids: dict[str, str]      # ios → PRODUCT_BUNDLE_IDENTIFIER

    @property
    def versions(self) -> set[str]:
        return {str(value) for value in self.values.values()}

    @property
    def version(self) -> str:
        """Die gemeinsame Nummer — oder ein Fehler, der jede abweichende Stelle nennt."""
        invalid = {name: value for name, value in self.values.items() if not is_version(value)}
        if invalid:
            listing = "; ".join(f"{name}: {value!r}" for name, value in invalid.items())
            raise VersionError(f"Ungültige Versionsnummer – erwartet x.y.z: {listing}")
        by_value: dict[str, dict[str, int]] = {}
        for name, value in self.values.items():
            files = by_value.setdefault(str(value), {})
            path = name.split(": ", 1)[0]
            files[path] = files.get(path, 0) + 1
        if len(by_value) > 1:
            lines = ["Die Versionsnummern sind nicht einheitlich:"]
            for value in sorted(by_value, key=version_key, reverse=True):
                files = ", ".join(f"{path} ({count}×)" if count > 1 else path for path, count in by_value[value].items())
                lines.append(f"  {value}  {files}")
            lines.append("Angleichen mit: python3 tools/nori-version.py set <x.y.z>")
            raise VersionError("\n".join(lines))
        return next(iter(by_value))

    @property
    def highest(self) -> str | None:
        valid = [str(value) for value in self.values.values() if is_version(value)]
        return max(valid, key=version_key) if valid else None


def read_state(commit: str | None = None, lenient: bool = False) -> State:
    """Alle Nummern eines Stands. `lenient` überspringt Stellen, die es dort noch nicht gab."""
    read = reader(commit)
    values: dict[str, object] = {}
    for location in LOCATIONS:
        try:
            text = read(location.path)
        except VersionError:
            if lenient:
                continue
            raise
        for field, value in read_location(location, text).items():
            values[f"{location.path}{': ' + field if field else ''}"] = value
    builds: dict[str, str] = {}
    bundle_ids: dict[str, str] = {}
    for platform, path in XCODE_PROJECTS.items():
        text = read(path)
        build = single_setting(text, "CURRENT_PROJECT_VERSION", path)
        if not BUILD_NUMBER.match(build):
            raise VersionError(f"Ungültige Buildnummer {build!r} in {path} – erwartet eine ganze Zahl ab 1")
        builds[platform] = build
        bundle_ids[platform] = single_setting(text, "PRODUCT_BUNDLE_IDENTIFIER", path)
    return State(values, builds, bundle_ids)


# ── Prüfen ───────────────────────────────────────────────────────────────────


def check_documents(version: str, read: Callable[[str], str]) -> list[str]:
    problems = []
    changelog = read(CHANGELOG)
    if not any(line.startswith("## ") and f"[Nori {version}]" in line for line in changelog.splitlines()):
        problems.append(f"{CHANGELOG} hat keinen Abschnitt `## [Nori {version}]` – ein Stand ohne Eintrag ist einer, dessen Änderungen niemand kennt")
    overview = changelog.split("\n## ", 1)[0]
    if f"Nori **{version}**" not in overview:
        problems.append(f"{CHANGELOG} nennt in der Übersicht am Anfang nicht `Nori **{version}**`")
    status = readme_status(read(README))
    if status is None:
        problems.append(f"{README} hat keinen Abschnitt „## Aktueller Stand“")
        return problems
    if f"Nori **{version}**" not in status:
        problems.append(f"{README} nennt unter „Aktueller Stand“ nicht `Nori **{version}**`")
    for row in README_ROWS:
        lines = [line for line in status.splitlines() if line.startswith(f"| {row} |")]
        if not lines:
            problems.append(f"{README}: Zeile „{row}“ fehlt unter „Aktueller Stand“")
        elif not all(f"**{version}**" in line for line in lines):
            problems.append(f"{README}: Zeile „{row}“ unter „Aktueller Stand“ nennt nicht **{version}**")
    return problems


def readme_status(readme: str) -> str | None:
    """Nur der Abschnitt „Aktueller Stand“ — weiter unten stehen Tabellen mit denselben Zeilennamen."""
    match = re.search(r"^## Aktueller Stand[ \t]*\n(.*?)(?=^## |\Z)", readme, re.MULTILINE | re.DOTALL)
    return match.group(1) if match else None


def changed_package_files(base: str, commit: str | None) -> list[str]:
    command = ["diff", "--name-only", base]
    if commit is not None:
        command.append(commit)
    result = git(*command, "--", *PACKAGE_PATHS)
    if result.returncode != 0:
        raise VersionError(f"git diff gegen {base} fehlgeschlagen: {result.stderr.strip()[:200]}")
    return [line for line in result.stdout.splitlines() if line]


def resolve(ref: str) -> str:
    result = git("rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")
    if result.returncode != 0:
        raise VersionError(f"{ref} ist nicht vorhanden – fehlt `fetch-depth: 0`?")
    return result.stdout.strip()


def check_against(state: State, version: str, against: str, commit: str | None) -> list[str]:
    """Wer ein Paket ändert, erhöht die Nummer — gegenüber jedem Stand in `against`."""
    target = resolve(against)
    base_result = git("merge-base", target, commit or "HEAD")
    base = base_result.stdout.strip() if base_result.returncode == 0 else target
    changed = changed_package_files(base, commit)
    if not changed:
        return []
    other = read_state(target, lenient=True)
    highest = other.highest
    problems = []
    if highest is not None and version_key(version) <= version_key(highest):
        sample = ", ".join(changed[:3]) + (" …" if len(changed) > 3 else "")
        problems.append(
            f"Pakete ändern sich gegenüber {against} ({sample}), die Nummer aber nicht: "
            f"{version} ist nicht größer als {highest}. Erst `python3 tools/nori-version.py bump patch|minor|major`."
        )
    for platform, build in state.builds.items():
        before = other.builds.get(platform)
        if before is not None and int(build) <= int(before):
            problems.append(
                f"Buildnummer {platform} {build} ist nicht größer als {before} in {against} – "
                "das System erkennt den Stand sonst nicht als neuer."
            )
    return problems


def check(expected: str | None = None, commit: str | None = None, against: str | None = None,
          documents: bool = True) -> State:
    wanted = normalize_version(expected) if expected is not None else None
    state = read_state(commit)
    version = state.version
    problems = []
    if wanted is not None and version != wanted:
        problems.append(f"Das Repository trägt {version}, verlangt ist {wanted}")
    if documents:
        problems += check_documents(version, reader(commit))
    if against:
        problems += check_against(state, version, against, commit)
    if problems:
        raise VersionError("\n".join(problems))
    return state


# ── Schreiben ────────────────────────────────────────────────────────────────


def write_location(location: Location, text: str, version: str) -> str:
    updated, count = re.subn(r"\bMARKETING_VERSION = [^;]*;", f"MARKETING_VERSION = {version};", text)
    if count < 1:
        raise VersionError(f"{location.path}: MARKETING_VERSION nicht gefunden")
    after = read_location(location, updated)
    if {str(value) for value in after.values()} != {version}:
        raise VersionError(f"{location.path}: nach dem Schreiben steht dort {after}")
    return updated


def write_build(text: str, build: int) -> str:
    updated, count = re.subn(r"\bCURRENT_PROJECT_VERSION = [^;]*;", f"CURRENT_PROJECT_VERSION = {build};", text)
    if count < 1:
        raise VersionError("CURRENT_PROJECT_VERSION nicht gefunden")
    return updated


def set_version(version: str, builds: dict[str, int] | None = None) -> dict[str, str]:
    """Setzt die gemeinsame Nummer überall und erhöht die Buildnummern.

    Die Nummer muss über dem höchsten vorhandenen Stand liegen — außer beim
    Angleichen: Steht sie nach einem Merge schon an einzelnen Stellen, während
    andere niedriger sind, wird der Baum auf sie gezogen. Ein **einheitlicher**
    Baum lässt sich damit nicht ein zweites Mal auf dieselbe Nummer setzen.
    """
    version = normalize_version(version)
    state = read_state()
    highest = state.highest
    aligning = highest is not None and version == highest and len(state.versions) > 1
    if highest is not None and version_key(version) <= version_key(highest) and not aligning:
        raise VersionError(
            f"{version} ist nicht größer als der höchste vorhandene Stand {highest} – "
            "keine Plattform wird zurückgestuft, und keine Nummer wird zweimal vergeben"
        )
    new_builds = {platform: int(value) + 1 for platform, value in state.builds.items()}
    for platform, value in (builds or {}).items():
        if value <= int(state.builds[platform]):
            raise VersionError(f"Buildnummer {platform} {value} ist nicht größer als {state.builds[platform]}")
        new_builds[platform] = value

    changes: dict[Path, str] = {}
    for location in LOCATIONS:
        path = ROOT / location.path
        text = changes.get(path, path.read_text(encoding="utf-8"))
        changes[path] = write_location(location, text, version)
    for platform, relative in XCODE_PROJECTS.items():
        path = ROOT / relative
        changes[path] = write_build(changes[path], new_builds[platform])
    for path, text in changes.items():
        path.write_text(text, encoding="utf-8")

    written = read_state()
    if written.version != version or {k: int(v) for k, v in written.builds.items()} != new_builds:
        raise VersionError("Nach dem Schreiben stimmen die Nummern nicht – bitte `git diff` ansehen")
    return {platform: str(value) for platform, value in new_builds.items()}


# ── Kommandozeile ────────────────────────────────────────────────────────────


def command_show(args) -> int:
    state = read_state(args.commit)
    width = max(len(name) for name in state.values)
    for name, value in state.values.items():
        print(f"{name:<{width}}  {value}")
    for platform, build in state.builds.items():
        print(f"{'Build ' + platform:<{width}}  {build}")
    try:
        print(f"\nGemeinsame Version: {state.version}")
    except VersionError as error:
        print(f"\n{error}")
        return 1
    return 0


def command_check(args) -> int:
    state = check(args.version, args.commit, args.against, documents=not args.no_documents)
    builds = ", ".join(f"{platform} {build}" for platform, build in state.builds.items())
    print(f"OK — Nori {state.version} an {len(state.values)} Stellen, Buildnummern {builds}.")
    return 0


def report_set(version: str, builds: dict[str, str]) -> None:
    print(f"Nori {version} gesetzt; Buildnummern: " + ", ".join(f"{k} {v}" for k, v in builds.items()))
    print("Noch von Hand: Abschnitt `## [Nori " + version + "]` in CHANGELOG.md, Übersicht dort und in README.md.")
    print("Danach: python3 tools/nori-version.py check")


def command_set(args) -> int:
    builds = {}
    if args.build_ios is not None:
        builds["ios"] = args.build_ios
    version = normalize_version(args.version)
    report_set(version, set_version(version, builds))
    return 0


def command_bump(args) -> int:
    state = read_state()
    current = state.highest
    if current is None:
        raise VersionError("Keine gültige Nummer gefunden, von der aus erhöht werden könnte")
    version = next_version(current, args.part)
    report_set(version, set_version(version))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    show = commands.add_parser("show", help="alle Stellen mit ihrer Nummer")
    show.add_argument("--commit")
    show.set_defaults(handler=command_show)

    check_parser = commands.add_parser("check", help="einheitlich, gültig, dokumentiert und erhöht?")
    check_parser.add_argument("--version", help="diese Nummer muss es sein (2.6.0 oder v2.6.0)")
    check_parser.add_argument("--commit", help="Stand dieses Commits statt der Arbeitskopie")
    check_parser.add_argument("--against", help="Pakete geändert? Dann Nummer größer als in diesem Stand")
    check_parser.add_argument("--no-documents", action="store_true", help="CHANGELOG und README nicht prüfen")
    check_parser.set_defaults(handler=command_check)

    set_parser = commands.add_parser("set", help="Nummer überall setzen, Buildnummern erhöhen")
    set_parser.add_argument("version")
    set_parser.add_argument("--build-ios", type=int)
    set_parser.set_defaults(handler=command_set)

    bump = commands.add_parser("bump", help="nächste Nummer nach Semantic Versioning")
    bump.add_argument("part", choices=("patch", "minor", "major"))
    bump.set_defaults(handler=command_bump)

    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except VersionError as error:
        prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") else "FEHLER "
        for line in str(error).splitlines():
            print(f"{prefix}{line}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
