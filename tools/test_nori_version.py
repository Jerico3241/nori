#!/usr/bin/env python3
"""Regressionstests für tools/nori-version.py.

Jeder Test baut sich ein Wegwerf-Repository mit allen Stellen, an denen die
Nori-Version steht. Nur `CurrentRepositoryTests` liest das echte Repository —
ohne etwas zu schreiben.

    python3 tools/test_nori_version.py
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "nori-version.py"
REPO = Path(__file__).resolve().parent.parent


def load_tool():
    spec = importlib.util.spec_from_file_location("nori_version_under_test", TOOL)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def git(root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), "-c", "user.name=Nori Test", "-c", "user.email=test@example.invalid",
         "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
        check=True, capture_output=True, text=True,
    )
    return result.stdout.strip()


def pbxproj(version: str, build: str, bundle: str, second_version: str | None = None) -> str:
    def block(marketing: str) -> str:
        return (f"\t\t\t\tCURRENT_PROJECT_VERSION = {build};\n\t\t\t\tMARKETING_VERSION = {marketing};\n"
                f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bundle};\n")
    return "// !$*UTF8*$!\n{\n" + block(version) + block(second_version or version) + "}\n"


def lockfile(name: str, version: str, linked: dict[str, str]) -> str:
    packages = {"": {"name": name, "version": version, "dependencies": {"react": "^18.3.1"}}}
    for path, package in linked.items():
        packages[path] = {"name": package, "version": version, "devDependencies": {"typescript": "^5.6.3"}}
    packages["node_modules/react"] = {"version": "18.3.1", "resolved": "https://example.invalid/react.tgz"}
    document = {"name": name, "version": version, "lockfileVersion": 3, "requires": True, "packages": packages}
    return json.dumps(document, indent=2, ensure_ascii=False) + "\n"


def changelog(version: str) -> str:
    return (f"# Changelog\n\nAlle Plattformen tragen Nori **{version}**.\n\n"
            f"## [Nori {version}] — 2026-09-17\n\n### Allgemein\n\n- Eine Nummer für alle.\n")


def readme(version: str, windows: str | None = None) -> str:
    return (
        "# Nori\n\n## Aktueller Stand\n\n"
        f"Nori **{version}** auf allen Plattformen.\n\n"
        "| Plattform | Version |\n| --- | --- |\n"
        f"| iOS / iPadOS | **{version}** |\n| macOS | **{version}** |\n"
        f"| Windows | **{windows or version}** |\n| LG webOS | **{version}** |\n\n"
        "## Google-Anmeldung\n\n| Plattform | Fluss |\n| --- | --- |\n"
        "| iOS / iPadOS | PKCE |\n| macOS | Loopback |\n"
    )


def files_for(version: str, ios_build: str = "40", mac_build: str = "31") -> dict[str, str]:
    package = lambda name: json.dumps({"name": name, "version": version, "private": True}, indent=2) + "\n"  # noqa: E731
    return {
        "native/Nori-iOS/Nori.xcodeproj/project.pbxproj": pbxproj(version, ios_build, "to.nori.ios"),
        "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj": pbxproj(version, mac_build, "to.nori.macos"),
        "native/Nori-macOS/Sources/Features/Settings/SettingsView.swift":
            f'enum NoriRelease {{\n    static let version = "{version}"\n}}\n',
        "native/NoriCore/Sources/NoriCore/Models.swift": "struct Models {}\n",
        "native/Tests/NoriCoreTests/ModelsTests.swift": "// Test\n",
        "apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": version, "title": "Nori"}, indent=2) + "\n",
        "apps/webos/package.json": package("@nori/webos"),
        "apps/webos/package-lock.json": lockfile("@nori/webos", version, {
            "../../shared/nori-app": "@nori/app", "../../shared/nori-core": "@nori/core"}),
        "apps/webos/test/remote.test.mjs": "// Fernbedienung\n",
        "apps/windows/package.json": package("@nori/windows"),
        "apps/windows/package-lock.json": lockfile("@nori/windows", version, {
            "../../shared/nori-app": "@nori/app", "../../shared/nori-core": "@nori/core"}),
        "package.json": package("nori"),
        # Wie das echte: ein Feld auf einer Zeile, das json.dumps umbrechen würde.
        "shared/nori-core/package.json":
            '{\n  "name": "@nori/core",\n  "version": "' + version + '",\n  "files": ["dist"]\n}\n',
        "shared/nori-core/package-lock.json": lockfile("@nori/core", version, {}),
        "shared/nori-core/src/index.ts": "export {};\n",
        "shared/nori-core/test/fixtures.ts": "export {};\n",
        "shared/nori-app/package.json": package("@nori/app"),
        "services/nori-api/package.json": package("@nori/api"),
        "services/nori-api/package-lock.json": lockfile("@nori/api", version, {"../../shared/nori-core": "@nori/core"}),
        "services/nori-api/src/server.ts": f'export const API_VERSION = "{version}";\nconst other = "{version}";\n',
        "CHANGELOG.md": changelog(version),
        "README.md": readme(version),
        "docs/releases.md": "# Releases\n",
    }


class VersionTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tool = load_tool()
        self.temp = Path(tempfile.mkdtemp(prefix="nori-version-test-"))
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.repo = self.temp / "repo"
        self.repo.mkdir()
        self.write(files_for("2.6.0"))
        subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(self.repo)], check=True)
        self.commit("Stand")
        self.tool.ROOT = self.repo
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

    def write(self, files: dict[str, str]) -> None:
        for name, text in files.items():
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

    def commit(self, message: str = "Änderung") -> str:
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", message)
        return git(self.repo, "rev-parse", "HEAD")

    def read(self, name: str) -> str:
        return (self.repo / name).read_text(encoding="utf-8")


class NormalizeTests(VersionTestCase):
    def test_accepted_inputs(self) -> None:
        for value in ("2.6.0", "v2.6.0", " V2.6.0 ", "10.0.12", "0.0.1"):
            with self.subTest(value=value):
                self.assertEqual(self.tool.normalize_version(value).lstrip("v"), value.strip().lstrip("vV"))

    def test_rejected_inputs(self) -> None:
        for value in ("2.6", "2.6.0-beta", "02.6.0", "2.06.0", "vv2.6.0", "", None, "2.6.0.1", "latest",
                      "v 2.6.0", "2.6.0\n2.7.0", "2.6.x", "ios-v2.6.0"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(self.tool.VersionError, "Ungültige Version"):
                    self.tool.normalize_version(value)

    def test_next_version(self) -> None:
        self.assertEqual(self.tool.next_version("2.6.3", "patch"), "2.6.4")
        self.assertEqual(self.tool.next_version("2.6.3", "minor"), "2.7.0")
        self.assertEqual(self.tool.next_version("2.6.3", "major"), "3.0.0")
        with self.assertRaises(self.tool.VersionError):
            self.tool.next_version("2.6.3", "build")


class ReadTests(VersionTestCase):
    def test_unified_state(self) -> None:
        state = self.tool.check()
        self.assertEqual(state.version, "2.6.0")
        self.assertEqual(state.builds, {"ios": "40", "macos": "31"})
        self.assertEqual(state.bundle_ids, {"ios": "to.nori.ios", "macos": "to.nori.macos"})
        # Jede Stelle ist erfasst, auch die verlinkten Pakete in den Lockfiles.
        self.assertIn('apps/windows/package-lock.json: packages["../../shared/nori-core"].version', state.values)
        self.assertIn("services/nori-api/src/server.ts", state.values)
        self.assertIn("native/Nori-macOS/Sources/Features/Settings/SettingsView.swift", state.values)

    def test_every_location_is_checked(self) -> None:
        for location in self.tool.LOCATIONS:
            with self.subTest(path=location.path):
                original = self.read(location.path)
                if location.kind == "pbxproj":
                    changed = original.replace("MARKETING_VERSION = 2.6.0;", "MARKETING_VERSION = 2.5.9;", 1)
                elif location.kind == "lockfile":
                    changed = original.replace('"version": "2.6.0"', '"version": "2.5.9"', 1)
                else:
                    changed = original.replace("2.6.0", "2.5.9", 1)
                self.assertNotEqual(changed, original)
                self.write({location.path: changed})
                with self.assertRaisesRegex(self.tool.VersionError, r"nicht einheitlich[\s\S]*2\.5\.9  " + location.path):
                    self.tool.check()
                self.write({location.path: original})

    def test_linked_lockfile_package_is_checked(self) -> None:
        document = json.loads(self.read("apps/windows/package-lock.json"))
        document["packages"]["../../shared/nori-app"]["version"] = "2.4.0"
        self.write({"apps/windows/package-lock.json": json.dumps(document, indent=2) + "\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "2.4.0  apps/windows/package-lock.json"):
            self.tool.check()

    def test_invalid_numbers(self) -> None:
        self.write({"apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": "2.6"})})
        with self.assertRaisesRegex(self.tool.VersionError, "Ungültige Versionsnummer"):
            self.tool.check()

    def test_invalid_build(self) -> None:
        self.write({"native/Nori-iOS/Nori.xcodeproj/project.pbxproj": pbxproj("2.6.0", "40a", "to.nori.ios")})
        with self.assertRaisesRegex(self.tool.VersionError, "Ungültige Buildnummer"):
            self.tool.check()

    def test_inconsistent_build(self) -> None:
        text = pbxproj("2.6.0", "40", "to.nori.ios").replace("CURRENT_PROJECT_VERSION = 40;", "CURRENT_PROJECT_VERSION = 41;", 1)
        self.write({"native/Nori-iOS/Nori.xcodeproj/project.pbxproj": text})
        with self.assertRaisesRegex(self.tool.VersionError, "CURRENT_PROJECT_VERSION ist .* uneinheitlich"):
            self.tool.check()

    def test_pattern_must_be_unique(self) -> None:
        self.write({"services/nori-api/src/server.ts": 'export const API_VERSION = "2.6.0";\nexport const API_VERSION = "2.6.0";\n'})
        with self.assertRaisesRegex(self.tool.VersionError, "genau eine Fundstelle"):
            self.tool.check()

    def test_expected_version(self) -> None:
        self.tool.check("v2.6.0")
        with self.assertRaisesRegex(self.tool.VersionError, "trägt 2.6.0, verlangt ist 2.6.1"):
            self.tool.check("2.6.1")
        with self.assertRaisesRegex(self.tool.VersionError, "Ungültige Version"):
            self.tool.check("2.6")

    def test_reads_a_commit_not_the_worktree(self) -> None:
        commit = git(self.repo, "rev-parse", "HEAD")
        self.write({"apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": "9.9.9"})})
        self.assertEqual(self.tool.check(commit=commit).version, "2.6.0")
        with self.assertRaises(self.tool.VersionError):
            self.tool.check()


class DocumentTests(VersionTestCase):
    def test_changelog_section_is_required(self) -> None:
        self.write({"CHANGELOG.md": changelog("2.6.0").replace("## [Nori 2.6.0]", "## [webOS 2.6.0]")})
        with self.assertRaisesRegex(self.tool.VersionError, r"keinen Abschnitt `## \[Nori 2.6.0\]`"):
            self.tool.check()
        self.tool.check(documents=False)

    def test_changelog_overview_is_required(self) -> None:
        self.write({"CHANGELOG.md": changelog("2.6.0").replace("Nori **2.6.0**", "Nori **2.5.0**")})
        with self.assertRaisesRegex(self.tool.VersionError, "Übersicht"):
            self.tool.check()

    def test_readme_rows_in_status_section_only(self) -> None:
        self.write({"README.md": readme("2.6.0", windows="2.0.0")})
        with self.assertRaisesRegex(self.tool.VersionError, "Zeile „Windows“"):
            self.tool.check()
        # Die Tabelle weiter unten hat dieselben Zeilennamen ohne Nummer — das ist kein Fehler.
        self.write({"README.md": readme("2.6.0")})
        self.tool.check()

    def test_readme_needs_status_section(self) -> None:
        self.write({"README.md": "# Nori\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "Aktueller Stand"):
            self.tool.check()


class SetTests(VersionTestCase):
    def test_set_updates_every_location_and_builds(self) -> None:
        before = {name: self.read(name) for name in ("shared/nori-core/package.json", "services/nori-api/src/server.ts")}
        builds = self.tool.set_version("v2.7.0")
        self.assertEqual(builds, {"ios": "41", "macos": "32"})
        self.write({"CHANGELOG.md": changelog("2.7.0"), "README.md": readme("2.7.0")})
        state = self.tool.check("2.7.0")
        self.assertEqual(state.builds, {"ios": "41", "macos": "32"})
        # Nur die Nummer ändert sich: das Feld auf einer Zeile bleibt, der zweite Wert in server.ts auch.
        self.assertEqual(self.read("shared/nori-core/package.json"),
                         before["shared/nori-core/package.json"].replace("2.6.0", "2.7.0"))
        self.assertIn('const other = "2.6.0";', self.read("services/nori-api/src/server.ts"))
        lock = json.loads(self.read("apps/webos/package-lock.json"))
        self.assertEqual(lock["packages"]["node_modules/react"]["version"], "18.3.1")
        self.assertEqual(lock["packages"]["../../shared/nori-core"]["version"], "2.7.0")

    def test_set_never_downgrades_or_repeats(self) -> None:
        for version in ("2.6.0", "2.5.9", "1.0.0"):
            with self.subTest(version=version):
                with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
                    self.tool.set_version(version)
        self.assertEqual(self.tool.check().version, "2.6.0")

    def test_set_aligns_a_mixed_tree_to_a_number_it_already_carries(self) -> None:
        # Der Fall nach einem Merge: einzelne Stellen tragen die neue Nummer schon,
        # die übrigen kommen vom anderen Zweig.
        self.write({"apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": "2.5.0"}, indent=2) + "\n",
                    "apps/windows/package.json": json.dumps({"name": "@nori/windows", "version": "2.1.0"}, indent=2) + "\n"})
        self.assertEqual(self.tool.set_version("2.6.0"), {"ios": "41", "macos": "32"})
        self.assertEqual(self.tool.check(documents=False).version, "2.6.0")
        # Ein einheitlicher Baum lässt sich danach nicht noch einmal darauf setzen.
        with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
            self.tool.set_version("2.6.0")

    def test_set_never_lowers_a_mixed_tree(self) -> None:
        self.write({"apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": "2.8.0"}, indent=2) + "\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
            self.tool.set_version("2.6.0")

    def test_set_from_mixed_state_uses_the_highest(self) -> None:
        self.write({"native/Nori-iOS/Nori.xcodeproj/project.pbxproj": pbxproj("1.25.2", "39", "to.nori.ios"),
                    "apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": "2.6.3"}, indent=2) + "\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "höchste vorhandene Stand 2.6.3"):
            self.tool.set_version("2.6.1")
        self.tool.set_version("2.6.4")
        self.assertEqual(self.tool.check(documents=False).version, "2.6.4")

    def test_explicit_builds_must_increase(self) -> None:
        with self.assertRaisesRegex(self.tool.VersionError, "Buildnummer ios 40"):
            self.tool.set_version("2.7.0", {"ios": 40})
        self.assertEqual(self.tool.set_version("2.7.0", {"ios": 50}), {"ios": "50", "macos": "32"})

    def test_bump_command(self) -> None:
        self.assertEqual(self.tool.main(["bump", "minor"]), 0)
        self.assertEqual(self.tool.check(documents=False).version, "2.7.0")
        self.assertEqual(self.tool.main(["bump", "patch"]), 0)
        self.assertEqual(self.tool.check(documents=False).version, "2.7.1")
        self.assertEqual(self.tool.main(["bump", "major"]), 0)
        self.assertEqual(self.tool.check(documents=False).version, "3.0.0")

    def test_lockfile_not_written_by_npm_is_refused(self) -> None:
        self.write({"shared/nori-core/package-lock.json": '{"name": "@nori/core", "version": "2.6.0", "packages": {}}\n'})
        with self.assertRaisesRegex(self.tool.VersionError, "nicht im Format von npm"):
            self.tool.set_version("2.7.0")


class AgainstTests(VersionTestCase):
    def setUp(self) -> None:
        super().setUp()
        git(self.repo, "branch", "base")
        git(self.repo, "checkout", "-q", "-b", "feature")

    def test_package_change_requires_a_higher_version(self) -> None:
        self.write({"apps/webos/src/App.tsx": "export {};\n"})
        self.commit()
        with self.assertRaisesRegex(self.tool.VersionError, "2.6.0 ist nicht größer als 2.6.0"):
            self.tool.check(commit="HEAD", against="base")
        self.tool.set_version("2.6.1")
        self.write({"CHANGELOG.md": changelog("2.6.1"), "README.md": readme("2.6.1")})
        self.commit()
        self.tool.check(commit="HEAD", against="base")

    def test_worktree_changes_count_too(self) -> None:
        self.write({"shared/nori-core/src/index.ts": "export const x = 1;\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
            self.tool.check(against="base")

    def test_tests_and_documents_need_no_new_version(self) -> None:
        self.write({"apps/webos/test/remote.test.mjs": "// neu\n", "docs/releases.md": "# neu\n",
                    "native/Tests/NoriCoreTests/ModelsTests.swift": "// neu\n",
                    "shared/nori-core/test/fixtures.ts": "export const y = 1;\n"})
        self.commit()
        self.tool.check(commit="HEAD", against="base")

    def test_builds_must_increase_with_the_version(self) -> None:
        self.write({"apps/windows/src/main.ts": "export {};\n"})
        self.tool.set_version("2.6.1", {"ios": 41, "macos": 32})
        self.write({"CHANGELOG.md": changelog("2.6.1"), "README.md": readme("2.6.1"),
                    "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj": pbxproj("2.6.1", "31", "to.nori.macos")})
        self.commit()
        with self.assertRaisesRegex(self.tool.VersionError, "Buildnummer macos 31 ist nicht größer als 31"):
            self.tool.check(commit="HEAD", against="base")

    def test_base_without_newer_locations_and_with_mixed_versions(self) -> None:
        git(self.repo, "checkout", "-q", "base")
        (self.repo / "shared/nori-app/package.json").unlink()
        self.write({"native/Nori-iOS/Nori.xcodeproj/project.pbxproj": pbxproj("1.25.2", "39", "to.nori.ios"),
                    "apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": "2.4.1"}, indent=2) + "\n"})
        self.commit("alter Stand")
        git(self.repo, "checkout", "-q", "feature")
        self.write({"apps/webos/src/App.tsx": "export {};\n"})
        self.commit()
        # 2.6.0 liegt über dem höchsten Stand 2.6.0? Nein — die übrigen Stellen tragen dort 2.6.0.
        with self.assertRaisesRegex(self.tool.VersionError, "nicht größer als 2.6.0"):
            self.tool.check(commit="HEAD", against="base")

    def test_missing_ref_is_an_error(self) -> None:
        with self.assertRaisesRegex(self.tool.VersionError, "nicht vorhanden"):
            self.tool.check(against="origin/gibt-es-nicht")


class CommandTests(VersionTestCase):
    def test_check_command_exit_codes(self) -> None:
        self.assertEqual(self.tool.main(["check", "--version", "2.6.0"]), 0)
        self.assertEqual(self.tool.main(["check", "--version", "2.6.1"]), 1)
        self.assertEqual(self.tool.main(["check", "--version", "v2"]), 1)
        self.assertEqual(self.tool.main(["show"]), 0)

    def test_set_command_rejects_bad_input(self) -> None:
        self.assertEqual(self.tool.main(["set", "2.6"]), 1)
        self.assertEqual(self.tool.main(["set", "2.5.0"]), 1)
        self.assertEqual(self.tool.check().version, "2.6.0")


class CurrentRepositoryTests(unittest.TestCase):
    """Das echte Repository trägt eine einheitliche, dokumentierte Nummer."""

    def test_current_repository_is_consistent(self) -> None:
        tool = load_tool()
        tool.ROOT = REPO
        state = tool.check()
        self.assertTrue(tool.SEMVER.match(state.version))
        self.assertEqual(set(state.builds), {"ios", "macos"})


if __name__ == "__main__":
    unittest.main()
