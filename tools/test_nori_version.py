#!/usr/bin/env python3
"""Regressionstests für tools/nori-version.py.

Jeder Test baut sich ein Wegwerf-Repository mit der Stelle, an der die
Nori-Version steht. Nur `CurrentRepositoryTests` liest das echte Repository —
ohne etwas zu schreiben.

    python3 tools/test_nori_version.py
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
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


IOS = "native/Nori-iOS/Nori.xcodeproj/project.pbxproj"


def changelog(version: str) -> str:
    return (f"# Changelog\n\nAktuell: Nori **{version}**.\n\n"
            f"## [Nori {version}] — 2026-09-17\n\n### Allgemein\n\n- Eine Nummer.\n")


def readme(version: str, ios: str | None = None) -> str:
    return (
        "# Nori\n\n## Aktueller Stand\n\n"
        f"Nori **{version}**.\n\n"
        "| Plattform | Version |\n| --- | --- |\n"
        f"| iOS / iPadOS | **{ios or version}** |\n\n"
        "## Google-Anmeldung\n\n| Plattform | Fluss |\n| --- | --- |\n"
        "| iOS / iPadOS | PKCE |\n"
    )


def files_for(version: str, ios_build: str = "40") -> dict[str, str]:
    return {
        IOS: pbxproj(version, ios_build, "to.nori.ios"),
        "native/Nori-iOS/Sources/App.swift": "struct App {}\n",
        "native/Nori-iOS/README.md": "# iOS\n",
        "native/NoriCore/Sources/NoriCore/Models.swift": "struct Models {}\n",
        "native/Tests/NoriCoreTests/ModelsTests.swift": "// Test\n",
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
        self.assertEqual(state.builds, {"ios": "40"})
        self.assertEqual(state.bundle_ids, {"ios": "to.nori.ios"})
        # Beide Konfigurationen (Debug und Release) sind erfasst.
        self.assertEqual(len(state.values), 2)

    def test_every_marketing_version_is_checked(self) -> None:
        self.write({IOS: pbxproj("2.6.0", "40", "to.nori.ios", second_version="2.5.9")})
        with self.assertRaisesRegex(self.tool.VersionError, r"nicht einheitlich[\s\S]*2\.5\.9  " + IOS):
            self.tool.check()

    def test_invalid_numbers(self) -> None:
        self.write({IOS: pbxproj("2.6", "40", "to.nori.ios")})
        with self.assertRaisesRegex(self.tool.VersionError, "Ungültige Versionsnummer"):
            self.tool.check()

    def test_invalid_build(self) -> None:
        self.write({IOS: pbxproj("2.6.0", "40a", "to.nori.ios")})
        with self.assertRaisesRegex(self.tool.VersionError, "Ungültige Buildnummer"):
            self.tool.check()

    def test_inconsistent_build(self) -> None:
        text = pbxproj("2.6.0", "40", "to.nori.ios").replace("CURRENT_PROJECT_VERSION = 40;", "CURRENT_PROJECT_VERSION = 41;", 1)
        self.write({IOS: text})
        with self.assertRaisesRegex(self.tool.VersionError, "CURRENT_PROJECT_VERSION ist .* uneinheitlich"):
            self.tool.check()

    def test_missing_marketing_version(self) -> None:
        self.write({IOS: "// !$*UTF8*$!\n{\n\t\t\t\tCURRENT_PROJECT_VERSION = 40;\n}\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "MARKETING_VERSION fehlt"):
            self.tool.check()

    def test_expected_version(self) -> None:
        self.tool.check("v2.6.0")
        with self.assertRaisesRegex(self.tool.VersionError, "trägt 2.6.0, verlangt ist 2.6.1"):
            self.tool.check("2.6.1")
        with self.assertRaisesRegex(self.tool.VersionError, "Ungültige Version"):
            self.tool.check("2.6")

    def test_reads_a_commit_not_the_worktree(self) -> None:
        commit = git(self.repo, "rev-parse", "HEAD")
        self.write({IOS: pbxproj("9.9.9", "40", "to.nori.ios", second_version="2.6.0")})
        self.assertEqual(self.tool.check(commit=commit).version, "2.6.0")
        with self.assertRaises(self.tool.VersionError):
            self.tool.check()


class DocumentTests(VersionTestCase):
    def test_changelog_section_is_required(self) -> None:
        self.write({"CHANGELOG.md": changelog("2.6.0").replace("## [Nori 2.6.0]", "## [iOS 2.6.0]")})
        with self.assertRaisesRegex(self.tool.VersionError, r"keinen Abschnitt `## \[Nori 2.6.0\]`"):
            self.tool.check()
        self.tool.check(documents=False)

    def test_changelog_overview_is_required(self) -> None:
        self.write({"CHANGELOG.md": changelog("2.6.0").replace("Nori **2.6.0**", "Nori **2.5.0**")})
        with self.assertRaisesRegex(self.tool.VersionError, "Übersicht"):
            self.tool.check()

    def test_readme_rows_in_status_section_only(self) -> None:
        self.write({"README.md": readme("2.6.0", ios="2.0.0")})
        with self.assertRaisesRegex(self.tool.VersionError, "Zeile „iOS / iPadOS“"):
            self.tool.check()
        # Die Tabelle weiter unten hat denselben Zeilennamen ohne Nummer — das ist kein Fehler.
        self.write({"README.md": readme("2.6.0")})
        self.tool.check()

    def test_readme_needs_status_section(self) -> None:
        self.write({"README.md": "# Nori\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "Aktueller Stand"):
            self.tool.check()


class SetTests(VersionTestCase):
    def test_set_updates_every_location_and_builds(self) -> None:
        builds = self.tool.set_version("v2.7.0")
        self.assertEqual(builds, {"ios": "41"})
        self.write({"CHANGELOG.md": changelog("2.7.0"), "README.md": readme("2.7.0")})
        state = self.tool.check("2.7.0")
        self.assertEqual(state.builds, {"ios": "41"})
        self.assertEqual(state.bundle_ids, {"ios": "to.nori.ios"})

    def test_set_never_downgrades_or_repeats(self) -> None:
        for version in ("2.6.0", "2.5.9", "1.0.0"):
            with self.subTest(version=version):
                with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
                    self.tool.set_version(version)
        self.assertEqual(self.tool.check().version, "2.6.0")

    def test_set_aligns_a_mixed_tree_to_a_number_it_already_carries(self) -> None:
        # Der Fall nach einem Merge: eine Konfiguration trägt die neue Nummer schon.
        self.write({IOS: pbxproj("2.6.0", "40", "to.nori.ios", second_version="2.5.0")})
        self.assertEqual(self.tool.set_version("2.6.0"), {"ios": "41"})
        self.assertEqual(self.tool.check(documents=False).version, "2.6.0")
        # Ein einheitlicher Baum lässt sich danach nicht noch einmal darauf setzen.
        with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
            self.tool.set_version("2.6.0")

    def test_set_never_lowers_a_mixed_tree(self) -> None:
        self.write({IOS: pbxproj("2.6.0", "40", "to.nori.ios", second_version="2.8.0")})
        with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
            self.tool.set_version("2.6.0")

    def test_set_from_mixed_state_uses_the_highest(self) -> None:
        self.write({IOS: pbxproj("1.25.2", "39", "to.nori.ios", second_version="2.6.3")})
        with self.assertRaisesRegex(self.tool.VersionError, "höchste vorhandene Stand 2.6.3"):
            self.tool.set_version("2.6.1")
        self.tool.set_version("2.6.4")
        self.assertEqual(self.tool.check(documents=False).version, "2.6.4")

    def test_explicit_builds_must_increase(self) -> None:
        with self.assertRaisesRegex(self.tool.VersionError, "Buildnummer ios 40"):
            self.tool.set_version("2.7.0", {"ios": 40})
        self.assertEqual(self.tool.set_version("2.7.0", {"ios": 50}), {"ios": "50"})

    def test_bump_command(self) -> None:
        self.assertEqual(self.tool.main(["bump", "minor"]), 0)
        self.assertEqual(self.tool.check(documents=False).version, "2.7.0")
        self.assertEqual(self.tool.main(["bump", "patch"]), 0)
        self.assertEqual(self.tool.check(documents=False).version, "2.7.1")
        self.assertEqual(self.tool.main(["bump", "major"]), 0)
        self.assertEqual(self.tool.check(documents=False).version, "3.0.0")


class AgainstTests(VersionTestCase):
    def setUp(self) -> None:
        super().setUp()
        git(self.repo, "branch", "base")
        git(self.repo, "checkout", "-q", "-b", "feature")

    def test_package_change_requires_a_higher_version(self) -> None:
        self.write({"native/Nori-iOS/Sources/App.swift": "struct App { let x = 1 }\n"})
        self.commit()
        with self.assertRaisesRegex(self.tool.VersionError, "2.6.0 ist nicht größer als 2.6.0"):
            self.tool.check(commit="HEAD", against="base")
        self.tool.set_version("2.6.1")
        self.write({"CHANGELOG.md": changelog("2.6.1"), "README.md": readme("2.6.1")})
        self.commit()
        self.tool.check(commit="HEAD", against="base")

    def test_worktree_changes_count_too(self) -> None:
        self.write({"native/NoriCore/Sources/NoriCore/Models.swift": "struct Models { let x = 1 }\n"})
        with self.assertRaisesRegex(self.tool.VersionError, "nicht größer"):
            self.tool.check(against="base")

    def test_tests_and_documents_need_no_new_version(self) -> None:
        self.write({"docs/releases.md": "# neu\n", "native/Nori-iOS/README.md": "# neu\n",
                    "native/Tests/NoriCoreTests/ModelsTests.swift": "// neu\n"})
        self.commit()
        self.tool.check(commit="HEAD", against="base")

    def test_builds_must_increase_with_the_version(self) -> None:
        self.write({"native/Nori-iOS/Sources/App.swift": "struct App { let x = 1 }\n"})
        self.write({IOS: pbxproj("2.6.1", "40", "to.nori.ios"),
                    "CHANGELOG.md": changelog("2.6.1"), "README.md": readme("2.6.1")})
        self.commit()
        with self.assertRaisesRegex(self.tool.VersionError, "Buildnummer ios 40 ist nicht größer als 40"):
            self.tool.check(commit="HEAD", against="base")

    def test_base_with_mixed_versions(self) -> None:
        git(self.repo, "checkout", "-q", "base")
        self.write({IOS: pbxproj("1.25.2", "39", "to.nori.ios", second_version="2.6.0")})
        self.commit("alter Stand")
        git(self.repo, "checkout", "-q", "feature")
        self.write({"native/Nori-iOS/Sources/App.swift": "struct App { let x = 1 }\n"})
        self.commit()
        # Maßgeblich ist die höchste Nummer im Vergleichsstand, nicht die erste.
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
        self.assertEqual(set(state.builds), {"ios"})


if __name__ == "__main__":
    unittest.main()
