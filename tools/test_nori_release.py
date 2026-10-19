#!/usr/bin/env python3
"""Regressionstests für tools/nori-release.py — ohne echte Releases, Tags oder Löschungen.

GitHub ist durch einen Nachbau im Speicher ersetzt (`FakeGitHub`), das
Repository durch ein Wegwerf-Repository im Temp-Ordner. Pakete, Client-IDs,
Secrets und Tokens sind erfunden und werden zur Laufzeit zusammengesetzt, damit
keine Prüfung des Repositorys sie für echte hält. Kein Test liest
`~/.config/nori/secrets`.

Nur `GitHubRequestTests` spricht HTTP — mit einem lokalen Server auf 127.0.0.1.
`WorkflowTests` und `CurrentRepositoryTests` lesen die echten Workflows und den
echten Stand, schreiben aber nichts.

    python3 tools/test_nori_release.py
"""

from __future__ import annotations

import contextlib
import hashlib
import http.server
import importlib.util
import io
import json
import os
import plistlib
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.request
import zipfile
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parent
TOOL = TOOLS / "nori-release.py"
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
from test_nori_version import changelog as version_changelog, files_for, git  # noqa: E402
from test_nori_version import pbxproj as pbxproj_text  # noqa: E402

SUFFIX = ".apps.googleusercontent.com"
SECRET_PREFIX = "GOCSPX" + "-"

IOS_ID = "222222222222-" + "iosclien" * 4 + SUFFIX
MAC_ID = "333333333333-" + "macclien" * 4 + SUFFIX
MAC_SECRET = SECRET_PREFIX + "macSecretFake" + "M" * 16
TV_ID = "111111111111-" + "tvclient" * 4 + SUFFIX
TV_SECRET = SECRET_PREFIX + "tvSecretFake" + "T" * 16
ACCESS_TOKEN = "ya" + "29." + "a" * 32
REFRESH_TOKEN = "1/" + "/0" + "r" * 32
OTHER_COMMIT = "b" * 40
VERSION = "2.6.0"
ALL = ["ios"]

CHANGELOG_SECTION = """## [Nori 2.6.0] — 2026-09-17

Eine Nummer für alle Plattformen, z. B. iOS und webOS. Der OAuth-Fluss bleibt gleich.

### Allgemein

- **Ein Release je Version.** Alle Pakete hängen an einem Release.
- Der Runner schreibt die Zugangsdaten aus `~/.config/nori/secrets`.

### iOS / iPadOS

- Version 2.6.0, Build 40.
  - Unterpunkt ohne Einzelheiten.
  - Unterpunkt über den Refresh-Token.

### Windows

- **Installer und ZIP.** Beide tragen 2.6.0.

```bash
python3 tools/configure-google-oauth.py --ios
```

### Technische Änderungen

| Bereich | Änderung |
| --- | --- |
| Build-System | ein zentraler Release |

### Tests

- 80 neue Tests.

## [webOS 2.4.1] — 2026-09-16

- Alter Abschnitt.
"""


def load_tool():
    spec = importlib.util.spec_from_file_location("nori_release_under_test", TOOL)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def make_repo(root: Path, version: str = VERSION) -> str:
    files = files_for(version)
    files["CHANGELOG.md"] = version_changelog(version).split("## ")[0] + CHANGELOG_SECTION.replace("2.6.0", version)
    files.update({
        "native/Package.swift": "// swift-tools-version:5.9\n",
        "native/Tests/NoriCoreTests/ModelsTests.swift": f"let fake = \"{ACCESS_TOKEN}\"\n",
        "config/contract.json": "{}\n",
    })
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(root)], check=True)
    git(root, "add", "-A")
    git(root, "commit", "-qm", "Stand")
    return git(root, "rev-parse", "HEAD")


def make_secrets(directory: Path) -> None:
    # Neben der iOS-Client-ID liegen auf dem Rechner noch die Zugangsdaten der
    # entfernten Plattformen. In einem Paket hat keine davon etwas verloren.
    directory.mkdir()
    (directory / "google-webos-oauth.json").write_text(json.dumps({"installed": {"client_id": TV_ID, "client_secret": TV_SECRET}}))
    (directory / "google-macos-oauth.json").write_text(json.dumps({"installed": {"client_id": MAC_ID, "client_secret": MAC_SECRET}}))
    (directory / "google-ios-client-id").write_text(IOS_ID + "\n")


def make_ipa(directory: Path, version: str = VERSION, build: str = "40", bundle: str = "to.nori.ios",
             name: str | None = None, extra: dict[str, bytes] | None = None, apps: tuple[str, ...] = ("Nori.app",)) -> Path:
    path = directory / (name or f"Nori-iOS-v{version}.ipa")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("Payload/", b"")
        for app in apps:
            info = {"CFBundleShortVersionString": version, "CFBundleVersion": build,
                    "CFBundleIdentifier": bundle, "GoogleClientID": IOS_ID}
            archive.writestr(f"Payload/{app}/Info.plist", plistlib.dumps(info, fmt=plistlib.FMT_BINARY))
            # Cookie-Namen im Programmcode sind erlaubt, nur Werte nicht.
            archive.writestr(f"Payload/{app}/Nori", b"\xcf\xfa\xed\xfe Set-Cookie cf_clearance=" + b"\0" * 64)
        for member, data in (extra or {}).items():
            archive.writestr(member, data)
    return path


class FakeGitHub:
    """GitHub im Speicher. `writes` hält fest, was ein echter Lauf verändert hätte."""

    def __init__(self, tool, main_commits=(), tags=None, releases=None):
        self.tool = tool
        self.main_commits = set(main_commits)
        self.tag_refs: dict[str, str] = dict(tags or {})
        self.release_list: list[dict] = [dict(release) for release in (releases or [])]
        self.blobs: dict[int, bytes] = {}
        self.writes: list[str] = []
        self.corrupt_upload = ""
        self.tag_race = False
        self.workflow_list: list[dict] = []
        self.run_lists: dict[int, list[dict]] = {}
        self.runs_by_id: dict[int, dict] = {}
        self.artifact_lists: dict[int, list[dict]] = {}
        self.pull_heads: set[str] = set()
        self.deleted_runs: list[int] = []
        self.deleted_artifacts: list[int] = []
        self.fail_delete: dict[int, Exception] = {}

    def find(self, release_id):
        return next(release for release in self.release_list if release["id"] == release_id)

    def tag_commit(self, tag):
        return self.tag_refs.get(tag)

    def tags(self):
        return list(self.tag_refs)

    def releases(self):
        return [dict(release) for release in self.release_list]

    def on_main(self, commit):
        return commit in self.main_commits

    def create_draft(self, meta, notes):
        self.writes.append("draft")
        release = {"id": len(self.release_list) + 1, "tag_name": meta.tag, "name": meta.title, "body": notes,
                   "draft": True, "prerelease": False, "assets": [], "target_commitish": meta.commit,
                   "html_url": f"https://github.invalid/releases/{meta.tag}"}
        self.release_list.append(release)
        return dict(release)

    def upload(self, release, path, name, content_type):
        self.writes.append(f"upload {name}")
        data = path.read_bytes()
        if self.corrupt_upload == name:
            data = data[::-1]
        asset_id = 100 * release["id"] + len(self.find(release["id"])["assets"])
        self.blobs[asset_id] = data
        asset = {"id": asset_id, "name": name, "size": path.stat().st_size, "state": "uploaded",
                 "digest": "sha256:" + hashlib.sha256(data).hexdigest(), "content_type": content_type}
        self.find(release["id"])["assets"].append(asset)
        return asset

    def assets(self, release):
        return [dict(asset) for asset in self.find(release["id"])["assets"]]

    def download_asset(self, asset):
        return self.blobs[asset["id"]]

    def create_tag(self, tag, commit, message):
        self.writes.append("tag")
        if self.tag_race or tag in self.tag_refs:
            raise self.tool.GitHubError(422, "GitHub POST /git/refs: HTTP 422 Reference already exists")
        self.tag_refs[tag] = commit

    def publish(self, release):
        self.writes.append("publish")
        stored = self.find(release["id"])
        stored["draft"] = False
        return dict(stored)

    def release_by_tag(self, tag):
        return next((dict(r) for r in self.release_list if r["tag_name"] == tag and not r["draft"]), None)

    # Actions

    def run(self, run_id):
        return self.runs_by_id.get(run_id)

    def workflows(self):
        return list(self.workflow_list)

    def runs(self):
        # Wie bei GitHub: quer über alle Workflows, auch die ohne Eintrag.
        return [dict(run) for items in self.run_lists.values() for run in items
                if run["id"] not in self.deleted_runs]

    def workflow_runs(self, workflow_id):
        return [dict(run) for run in self.run_lists.get(workflow_id, []) if run["id"] not in self.deleted_runs]

    def artifacts(self, run_id):
        return [dict(item) for item in self.artifact_lists.get(run_id, []) if item["id"] not in self.deleted_artifacts]

    def open_pull_heads(self):
        return set(self.pull_heads)

    def delete_run(self, run_id):
        if run_id in self.fail_delete:
            raise self.fail_delete[run_id]
        self.writes.append(f"delete run {run_id}")
        self.deleted_runs.append(run_id)

    def delete_artifact(self, artifact_id):
        self.writes.append(f"delete artifact {artifact_id}")
        self.deleted_artifacts.append(artifact_id)


class ReleaseTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.tool = load_tool()
        self.temp = Path(tempfile.mkdtemp(prefix="nori-release-test-"))
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.repo = self.temp / "repo"
        self.repo.mkdir()
        self.commit = make_repo(self.repo)
        self.tool.ROOT = self.repo
        self.tool.SECRETS_DIR = self.temp / "secrets"
        make_secrets(self.tool.SECRETS_DIR)
        self.production_calls: list[str] = []
        self.tool.production_check = lambda meta, spec, path: self.production_calls.append(path.name)
        self.out = self.temp / "out"
        self.out.mkdir()
        # patch.dict stellt die ganze Umgebung am Ende wieder her, auch die entfernten Einträge.
        self.enterContext(mock.patch.dict(os.environ, {}))
        for name in ("GITHUB_ACTIONS", "GITHUB_REF", "GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "GITHUB_RUN_ID",
                     "GITHUB_REPOSITORY"):
            os.environ.pop(name, None)
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

    def meta(self):
        return self.tool.read_meta("HEAD")

    def commit_files(self, files: dict[str, str]) -> None:
        for name, text in files.items():
            (self.repo / name).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / name).write_text(text, encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "Änderung")
        self.commit = git(self.repo, "rev-parse", "HEAD")

    def set_version(self, version: str) -> None:
        files = files_for(version, "41")
        files["CHANGELOG.md"] = version_changelog(version).split("## ")[0] + CHANGELOG_SECTION.replace("2.6.0", version)
        self.commit_files(files)

    def github(self, **kwargs) -> FakeGitHub:
        kwargs.setdefault("main_commits", {self.commit})
        return FakeGitHub(self.tool, **kwargs)

    def packages(self, platforms=ALL, directory: Path | None = None) -> tuple[Path, dict[str, str]]:
        directory = directory or self.out / "pakete"
        directory.mkdir(exist_ok=True)
        makers = {
            "ios": lambda: make_ipa(directory),
        }
        sums = {}
        for platform in platforms:
            for key in self.tool.PLATFORMS[platform].assets:
                path = makers[key]()
                sums[key] = hashlib.sha256(path.read_bytes()).hexdigest()
        return directory, sums

    def release(self, github: FakeGitHub, platforms=ALL, dry_run: bool = False, sums: dict | None = None,
                directory: Path | None = None):
        built, checksums = self.packages(platforms) if directory is None else (directory, sums)
        return self.tool.run_release(self.meta(), list(platforms), built, github,
                                     checksums if sums is None else sums, "owner/nori", dry_run)


class MetaTests(ReleaseTestCase):
    def test_version_tag_title_and_assets_come_from_the_commit(self) -> None:
        meta = self.meta()
        self.assertEqual((meta.version, meta.commit, meta.tag, meta.title), (VERSION, self.commit, "v2.6.0", "Nori v2.6.0"))
        self.assertEqual(meta.builds, {"ios": "40"})
        self.assertEqual(meta.bundle_ids, {"ios": "to.nori.ios"})
        self.assertEqual(sorted(self.tool.expected_assets(VERSION, ALL)), ["Nori-iOS-v2.6.0.ipa"])

    def test_every_asset_follows_the_naming_scheme(self) -> None:
        for key, spec in self.tool.ASSETS.items():
            with self.subTest(asset=key):
                self.assertRegex(spec.name("2.6.0"), r"^Nori-[A-Za-z]+(-[A-Za-z]+)?-v2\.6\.0\.[a-z]+$")
                self.assertRegex(spec.name("2.6.0", "-abc1234"), r"^Nori-[A-Za-z-]+-v2\.6\.0-abc1234\.[a-z]+$")

    def test_release_version_input_must_match(self) -> None:
        self.assertEqual(self.tool.read_meta("HEAD", "v2.6.0").version, VERSION)
        with self.assertRaisesRegex(self.tool.ReleaseError, "Verlangt ist Version 2.6.1, Commit .* trägt 2.6.0"):
            self.tool.read_meta("HEAD", "2.6.1")
        for bad in ("2.6", "2.6.0-rc1", "v02.6.0", "", "latest"):
            with self.subTest(value=bad):
                with self.assertRaisesRegex(self.tool.ReleaseError, "Ungültige Version"):
                    self.tool.read_meta("HEAD", bad)

    def test_mixed_versions_are_an_error(self) -> None:
        self.commit_files({"native/Nori-iOS/Nori.xcodeproj/project.pbxproj":
                           pbxproj_text(VERSION, "40", "to.nori.ios", second_version="2.6.1")})
        with self.assertRaisesRegex(self.tool.ReleaseError, "nicht einheitlich"):
            self.meta()

    def test_build_values_for_release_and_test_builds(self) -> None:
        meta = self.meta()
        release = self.tool.build_values(meta, self.tool.PLATFORMS["ios"], True)
        self.assertEqual(release["artifact"], "nori-release-ios")
        self.assertEqual(release["retention"], "1")
        self.assertEqual(release["asset"], "Nori-iOS-v2.6.0.ipa")
        self.assertEqual(release["asset_ios"], "Nori-iOS-v2.6.0.ipa")
        test = self.tool.build_values(meta, self.tool.PLATFORMS["ios"], False)
        short = self.commit[:7]
        self.assertEqual(test["asset"], f"Nori-iOS-v2.6.0-{short}.ipa")
        self.assertEqual(test["artifact"], f"Nori-iOS-v2.6.0-{short}")
        self.assertEqual(test["retention"], "3")
        self.assertEqual(test["build"], "40")

    def test_platform_input(self) -> None:
        self.assertEqual(self.tool.parse_platforms(" IOS,ios"), ["ios"])
        # Entfernte Plattformen sind unbekannt, nicht stillschweigend leer.
        for bad in ("", " , ", "android", "ios,tvos", "macos", "webos", "windows", "ios,windows"):
            with self.subTest(value=bad):
                with self.assertRaises(self.tool.ReleaseError):
                    self.tool.parse_platforms(bad)


class PrepareTests(ReleaseTestCase):
    def setUp(self) -> None:
        super().setUp()
        # Die Tags aus der Zeit getrennter Plattform-Releases, auf einem älteren Stand.
        git(self.repo, "checkout", "-q", "--detach")
        (self.repo / "native/Nori-iOS/Nori.xcodeproj/project.pbxproj").write_text(
            pbxproj_text("1.25.2", "39", "to.nori.ios"), encoding="utf-8")
        git(self.repo, "commit", "-qam", "alt")
        old = git(self.repo, "rev-parse", "HEAD")
        self.legacy = {}
        for tag in ("ios-v1.25.2", "macos-v1.20.1", "webos-v2.2.1", "Latest"):
            git(self.repo, "tag", "-a", tag, "-m", tag)
            self.legacy[tag] = old
        git(self.repo, "checkout", "-q", "main")

    def github(self, **kwargs) -> FakeGitHub:
        kwargs["tags"] = {**self.legacy, **kwargs.get("tags", {})}
        return super().github(**kwargs)

    def prepare(self, github: FakeGitHub, version: str = "v2.6.0", platforms: str = "ios"):
        return self.tool.prepare(version, platforms, github)

    def test_new_version_is_ready(self) -> None:
        github = self.github()
        meta, platforms = self.prepare(github)
        self.assertEqual((meta.version, meta.commit, platforms), (VERSION, self.commit, ["ios"]))
        self.assertEqual(self.tool.build_at_tag("ios-v1.25.2", "ios"), "39")
        self.assertEqual(github.writes, [])

    def test_existing_tag_release_or_draft(self) -> None:
        cases = (
            (dict(tags={"v2.6.0": self.commit}), "Tag v2.6.0 existiert bereits"),
            (dict(releases=[{"id": 1, "tag_name": "v2.6.0", "name": "Nori v2.6.0", "draft": False}]), "existiert bereits"),
            (dict(releases=[{"id": 1, "tag_name": "v2.6.0", "name": "Nori v2.6.0", "draft": True}]), "Entwurf"),
            (dict(releases=[{"id": 1, "tag_name": "anders", "name": "Nori v2.6.0", "draft": False}]), "existiert bereits"),
        )
        for kwargs, message in cases:
            with self.subTest(message=message):
                with self.assertRaisesRegex(self.tool.ReleaseError, message):
                    self.prepare(self.github(**kwargs))

    def test_same_or_higher_version_in_any_tag_scheme(self) -> None:
        # Auch die Tags entfernter Plattformen zählen: ihre Nummern sind vergeben.
        for tag, message in (("webos-v2.6.0", "bereits vergeben"), ("ios-v3.0.0", "nicht neuer als das vorhandene ios-v3.0.0"),
                             ("v2.10.0", "nicht neuer"), ("windows-v2.6.1", "nicht neuer"), ("macos-v2.6.0", "bereits vergeben")):
            with self.subTest(tag=tag):
                with self.assertRaisesRegex(self.tool.ReleaseError, message):
                    self.prepare(self.github(tags={tag: OTHER_COMMIT}))

    def test_build_numbers_must_exceed_earlier_release_tags(self) -> None:
        # Ein älterer Plattform-Tag auf einem Stand mit derselben Buildnummer.
        git(self.repo, "tag", "-a", "ios-v1.9.4", "-m", "alt")
        self.assertEqual(self.tool.build_at_tag("ios-v1.9.4", "ios"), "40")
        with self.assertRaisesRegex(self.tool.ReleaseError, "Buildnummer ios 40 ist nicht größer als 40 in ios-v1.9.4"):
            self.prepare(self.github(tags={"ios-v1.9.4": self.commit}))
        git(self.repo, "tag", "-a", "v1.0.0", "-m", "alt")
        with self.assertRaisesRegex(self.tool.ReleaseError, "Buildnummer ios 40 ist nicht größer als 40 in ios-v1.9.4"):
            self.prepare(self.github(tags={"ios-v1.9.4": self.commit, "v1.0.0": self.commit}))

    def test_tag_missing_locally_is_an_error(self) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, "lokal nicht vorhanden"):
            self.prepare(self.github(tags={"ios-v1.0.0": OTHER_COMMIT}))

    def test_older_tag_without_project_is_ignored(self) -> None:
        empty = self.temp / "leer"
        subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(empty)], check=True)
        (empty / "README.md").write_text("alt")
        git(empty, "add", "-A")
        git(empty, "commit", "-qm", "alt")
        git(empty, "tag", "v1.8.0")
        git(self.repo, "fetch", "-q", str(empty), "refs/tags/v1.8.0:refs/tags/v1.8.0")
        self.assertIsNone(self.tool.build_at_tag("v1.8.0", "ios"))
        self.prepare(self.github(tags={"v1.8.0": OTHER_COMMIT}))

    def test_missing_documents_block_the_release(self) -> None:
        self.commit_files({"CHANGELOG.md": "# Changelog\n\nNori **2.6.0**\n\n## [iOS 2.6.0]\n"})
        with self.assertRaisesRegex(self.tool.ReleaseError, r"keinen Abschnitt `## \[Nori 2.6.0\]`"):
            self.prepare(self.github())

    def test_wrong_input(self) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, "trägt 2.6.0"):
            self.prepare(self.github(), version="2.7.0")
        with self.assertRaisesRegex(self.tool.ReleaseError, "Ungültige Version"):
            self.prepare(self.github(), version="2.6")
        with self.assertRaisesRegex(self.tool.ReleaseError, "Keine Plattform"):
            self.prepare(self.github(), platforms="")

    def test_only_on_main_in_actions(self) -> None:
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/claude/test"}):
            with self.assertRaisesRegex(self.tool.ReleaseError, "nur auf main"):
                self.prepare(self.github())
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main"}):
            self.prepare(self.github())


class PublishTests(ReleaseTestCase):
    def test_one_release_with_all_packages_and_checksums(self) -> None:
        github = self.github(tags={"ios-v1.25.2": OTHER_COMMIT})
        self.assertEqual(self.release(github), "created")
        names = list(self.tool.expected_assets(VERSION, ALL))
        # Erst Entwurf und alle Anhänge, dann der Tag, zuletzt die Veröffentlichung.
        self.assertEqual(github.writes, ["draft", *(f"upload {name}" for name in names),
                                         f"upload {self.tool.CHECKSUMS}", "tag", "publish"])
        self.assertEqual(github.tag_refs["v2.6.0"], self.commit)
        [release] = github.release_list
        self.assertFalse(release["draft"])
        self.assertEqual((release["name"], release["tag_name"]), ("Nori v2.6.0", "v2.6.0"))
        self.assertEqual(sorted(a["name"] for a in release["assets"]), sorted(names + [self.tool.CHECKSUMS]))
        names = sorted(names)
        self.assertEqual(sorted(self.production_calls), sorted(names))
        sums = self.tool.parse_checksums(github.blobs[next(a["id"] for a in release["assets"] if a["name"] == self.tool.CHECKSUMS)].decode())
        self.assertEqual(sorted(sums), names)
        for asset in release["assets"]:
            if asset["name"] != self.tool.CHECKSUMS:
                self.assertEqual(asset["digest"], "sha256:" + sums[asset["name"]])
        # Keine plattformgetrennten Tags mehr.
        self.assertEqual(sorted(github.tag_refs), ["ios-v1.25.2", "v2.6.0"])

    def test_release_notes(self) -> None:
        github = self.github()
        self.release(github)
        body = github.release_list[0]["body"]
        for expected in ("**Nori 2.6.0** für iOS / iPadOS.",
                         f"[`{self.commit[:7]}`](https://github.com/owner/nori/commit/{self.commit})",
                         "| iOS / iPadOS | `Nori-iOS-v2.6.0.ipa` | Build 40. Unsigniert",
                         "Nicht enthalten: macOS (eingestellt), Windows (eingestellt), LG webOS (eingestellt), "
                         "Android (keine App in diesem Repository), Google TV",
                         "shasum -a 256 -c checksums-sha256.txt",
                         "### Allgemein", "- **Ein Release je Version.** Alle Pakete hängen an einem Release.",
                         "### iOS / iPadOS", "  - Unterpunkt ohne Einzelheiten.", "### Windows",
                         "| Build-System | ein zentraler Release |", "z. B. iOS und webOS."):
            self.assertIn(expected, body)
        for unexpected in ("OAuth", "Runner", "secrets", "Refresh-Token", "configure-google-oauth", "80 neue Tests",
                           "Alter Abschnitt", "für diesen Release nicht gebaut"):
            self.assertNotIn(unexpected, body)

    def test_missing_or_extra_package_blocks_the_release(self) -> None:
        empty = self.out / "leer"
        empty.mkdir()
        with self.assertRaisesRegex(self.tool.ReleaseError, "Es fehlen Pakete: Nori-iOS-v2.6.0.ipa"):
            self.release(self.github(), directory=empty, sums={})
        directory, sums = self.packages()
        (directory / "build.log").write_text("Protokoll")
        github = self.github()
        with self.assertRaisesRegex(self.tool.ReleaseError, "Unerwartete Dateien bei den Paketen: build.log"):
            self.release(github, directory=directory, sums=sums)
        self.assertEqual(github.writes, [])

    def test_checksum_from_package_job_is_required_and_must_match(self) -> None:
        directory, sums = self.packages()
        github = self.github()
        with self.assertRaisesRegex(self.tool.ReleaseError, "Prüfsumme aus dem Paket-Job fehlt für ios"):
            self.release(github, directory=directory, sums={})
        with self.assertRaisesRegex(self.tool.ReleaseError, "weicht vom geprüften Paket ab"):
            self.release(github, directory=directory, sums={"ios": "0" * 64})
        self.assertEqual(github.writes, [])

    def test_existing_release_is_never_duplicated_or_overwritten(self) -> None:
        github = self.github(tags={"v2.6.0": OTHER_COMMIT},
                             releases=[{"id": 7, "tag_name": "v2.6.0", "name": "Nori v2.6.0", "draft": False, "assets": []}])
        with self.assertRaisesRegex(self.tool.ReleaseError, "existiert bereits"):
            self.release(github)
        self.assertEqual(github.writes, [])
        self.assertEqual(github.tag_refs["v2.6.0"], OTHER_COMMIT)
        self.assertEqual(len(github.release_list), 1)

    def test_dry_run_writes_nothing(self) -> None:
        github = self.github()
        self.assertEqual(self.release(github, dry_run=True), "dry-run")
        self.assertEqual(github.writes, [])

    def test_commit_outside_main_is_an_error(self) -> None:
        github = self.github(main_commits=set())
        with self.assertRaisesRegex(self.tool.ReleaseError, "nicht auf main"):
            self.release(github)
        self.assertEqual(github.writes, [])

    def test_failed_production_check_blocks_the_release(self) -> None:
        def failing(meta, spec, path):
            if spec.key == "ios":
                raise self.tool.ReleaseError("Produktionsprüfung fehlgeschlagen")
        self.tool.production_check = failing
        github = self.github()
        with self.assertRaisesRegex(self.tool.ReleaseError, "Produktionsprüfung"):
            self.release(github)
        self.assertEqual(github.writes, [])

    def test_modified_upload_is_never_published(self) -> None:
        github = self.github()
        github.corrupt_upload = "Nori-iOS-v2.6.0.ipa"
        with self.assertRaisesRegex(self.tool.ReleaseError, "weicht vom geprüften Paket ab"):
            self.release(github)
        self.assertNotIn("tag", github.writes)
        self.assertNotIn("v2.6.0", github.tag_refs)
        self.assertTrue(github.release_list[0]["draft"])

    def test_tag_race_leaves_the_draft_unpublished(self) -> None:
        github = self.github()
        github.tag_race = True
        with self.assertRaisesRegex(self.tool.ReleaseError, "inzwischen vorhanden"):
            self.release(github)
        self.assertEqual(github.writes[-1], "tag")
        self.assertTrue(github.release_list[0]["draft"])

    def test_publish_command_requires_checksums_and_the_checked_out_commit(self) -> None:
        directory, sums = self.packages(["ios"])
        with mock.patch.object(self.tool, "github_from_environment", lambda: self.github()), \
                mock.patch.dict(os.environ, {"GITHUB_REPOSITORY": "owner/nori"}):
            code = self.tool.main(["publish", "--version", VERSION, "--platforms", "ios", "--dir", str(directory),
                                   "--sha256", "ios=", "--commit", self.commit])
            self.assertEqual(code, 1)
            code = self.tool.main(["publish", "--version", VERSION, "--platforms", "ios", "--dir", str(directory),
                                   "--sha256", f"ios={sums['ios']}", "--commit", OTHER_COMMIT])
            self.assertEqual(code, 1)
            code = self.tool.main(["publish", "--version", VERSION, "--platforms", "ios", "--dir", str(directory),
                                   "--sha256", f"ios={sums['ios']}", "--commit", self.commit, "--dry-run"])
            self.assertEqual(code, 0)


class VerifyTests(ReleaseTestCase):
    def assertRejected(self, key: str, path: Path, message: str) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, message):
            self.tool.verify_asset(self.meta(), self.tool.ASSETS[key], path)

    def test_valid_packages_pass(self) -> None:
        directory, sums = self.packages()
        for key, digest in sums.items():
            with self.subTest(asset=key):
                spec = self.tool.ASSETS[key]
                path = directory / spec.name(VERSION)
                self.assertEqual(self.tool.verify_asset(self.meta(), spec, path, "sha256:" + digest), digest)

    def test_test_builds_carry_the_commit(self) -> None:
        short = self.commit[:7]
        path = make_ipa(self.out, name=f"Nori-iOS-v2.6.0-{short}.ipa")
        self.tool.verify_asset(self.meta(), self.tool.ASSETS["ios"], path, suffix=f"-{short}")
        with self.assertRaisesRegex(self.tool.ReleaseError, "Falsches Paket"):
            self.tool.verify_asset(self.meta(), self.tool.ASSETS["ios"], path)

    def test_wrong_name(self) -> None:
        self.assertRejected("ios", make_ipa(self.out, name="Nori-iOS-2.6.0-unsigned.ipa"), "Falsches Paket")

    def test_checksum_must_match(self) -> None:
        ipa = make_ipa(self.out)
        with self.assertRaisesRegex(self.tool.ReleaseError, "Prüfsumme"):
            self.tool.verify_asset(self.meta(), self.tool.ASSETS["ios"], ipa, "0" * 64)
        with self.assertRaisesRegex(self.tool.ReleaseError, "ungültig"):
            self.tool.verify_asset(self.meta(), self.tool.ASSETS["ios"], ipa, "abc")

    def test_ipa_version_build_and_bundle(self) -> None:
        self.assertRejected("ios", make_ipa(self.out, version="2.6.0", build="39"), "CFBundleVersion")
        self.assertRejected("ios", make_ipa(self.out, bundle="to.nori.macos"), "Bundle-ID")
        self.assertRejected("ios", make_ipa(self.out, version="1.25.2", name="Nori-iOS-v2.6.0.ipa"), "CFBundleShortVersionString")

    def test_ipa_structure_and_forbidden_files(self) -> None:
        self.assertRejected("ios", make_ipa(self.out, apps=("Nori.app", "Other.app")), "genau Payload/Nori.app")
        self.assertRejected("ios", make_ipa(self.out, extra={"build.txt": b"x"}), "außerhalb von Payload")
        self.assertRejected("ios", make_ipa(self.out, extra={"Payload/../evil": b"x"}), "unzulässiger Pfad")
        for member in ("Payload/Nori.app/.env.local", "Payload/Nori.app/Config/Google.local.xcconfig",
                       "Payload/Nori.app/client_secret_1.json", "Payload/Nori.app/xcodebuild.log",
                       "Payload/Nori.app/test-shots/home.png", "Payload/Nori.app/embedded.mobileprovision"):
            with self.subTest(member=member):
                self.assertRejected("ios", make_ipa(self.out, extra={member: b"x"}), "unzulässige Datei")
        broken = self.out / "Nori-iOS-v2.6.0.ipa"
        broken.write_bytes(b"kein zip")
        self.assertRejected("ios", broken, "kein gültiges ZIP")

    def test_ipa_credentials_tokens_and_cookies(self) -> None:
        cases = {
            SECRET_PREFIX.encode() + b"inventedSecretValue123": "Client-Secret",
            MAC_ID.encode(): "google-macos-oauth.json client_id",
            ACCESS_TOKEN.encode(): "Access-Token",
            REFRESH_TOKEN.encode(): "Refresh-Token",
            b'{"device_code": "AH-1Ng2aBcDeFgHiJ"}': "Gerätecode",
            b"cf_clearance=" + b"c" * 40: "Cookie",
        }
        for content, message in cases.items():
            with self.subTest(message=message):
                self.assertRejected("ios", make_ipa(self.out, extra={"Payload/Nori.app/main.jsbundle": content}), message)

    def test_check_app(self) -> None:
        app = self.out / "Nori.app"
        app.mkdir()
        info = {"CFBundleShortVersionString": VERSION, "CFBundleVersion": "40", "CFBundleIdentifier": "to.nori.ios"}
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        self.tool.check_app("ios", app, self.meta())
        info["CFBundleVersion"] = "39"
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(self.tool.ReleaseError, "CFBundleVersion ist '39'"):
            self.tool.check_app("ios", app, self.meta())
        with self.assertRaisesRegex(self.tool.ReleaseError, "fehlt"):
            self.tool.check_app("ios", self.out / "Anders.app", self.meta())


class NotesTests(ReleaseTestCase):
    def test_missing_changelog_section_is_an_error(self) -> None:
        text = (self.repo / "CHANGELOG.md").read_text().replace("## [Nori 2.6.0]", "## [Nori 2.5.9]")
        self.commit_files({"CHANGELOG.md": text})
        with self.assertRaisesRegex(self.tool.ReleaseError, r"keinen Abschnitt \[Nori 2\.6\.0\]"):
            self.tool.build_notes(self.meta(), ALL, "owner/nori")

    def test_public_text_check_rejects_credentials(self) -> None:
        for text in (f"Wert {TV_ID}", f"Wert {SECRET_PREFIX}inventedSecretValue123", f"Wert {ACCESS_TOKEN}",
                     "Der OAuth-Client wurde getauscht.", "kopiert aus der .env.local", "läuft auf dem Runner"):
            with self.subTest(text=text[:20]):
                with self.assertRaises(self.tool.ReleaseError):
                    self.tool.check_public_text(text)
        self.tool.check_public_text("Die Liste lädt schneller.")

    def test_every_hint_is_public(self) -> None:
        for spec in self.tool.ASSETS.values():
            self.tool.check_public_text(spec.hint)
        for reason in self.tool.NOT_AVAILABLE.values():
            self.tool.check_public_text(reason)


class ValidateTests(ReleaseTestCase):
    def published(self, platforms=ALL) -> FakeGitHub:
        github = self.github()
        self.release(github, platforms=platforms)
        github.writes.clear()
        return github

    def test_published_release_is_complete(self) -> None:
        github = self.published()
        release = self.tool.validate_release(github, self.meta(), ALL)
        self.assertEqual(release["tag_name"], "v2.6.0")
        self.assertEqual(github.writes, [])

    def test_incomplete_or_wrong_releases(self) -> None:
        cases = (
            ("fehlendes Paket", lambda g: g.release_list[0]["assets"].pop(0), "unvollständig – fehlt"),
            ("zusätzlicher Anhang", lambda g: g.release_list[0]["assets"].append(
                {"id": 999, "name": "extra.bin", "size": 1, "state": "uploaded"}), "zu viel: extra.bin"),
            ("Entwurf", lambda g: g.release_list[0].update(draft=True), "nicht gefunden"),
            ("Vorabversion", lambda g: g.release_list[0].update(prerelease=True), "nicht veröffentlicht"),
            ("Tag verschoben", lambda g: g.tag_refs.update({"v2.6.0": OTHER_COMMIT}), "zeigt auf bbbbbbb"),
            ("Upload offen", lambda g: g.release_list[0]["assets"][1].update(state="starter"), "nicht vollständig hochgeladen"),
            ("Prüfsumme", lambda g: g.release_list[0]["assets"][0].update(digest="sha256:" + "0" * 64), "weicht von checksums"),
        )
        for label, change, message in cases:
            with self.subTest(case=label):
                github = self.published()
                change(github)
                with self.assertRaisesRegex(self.tool.ReleaseError, message):
                    self.tool.validate_release(github, self.meta(), ALL)

    def test_checksums_file_must_match_its_digest_and_the_packages(self) -> None:
        github = self.published()
        sums_asset = next(a for a in github.release_list[0]["assets"] if a["name"] == self.tool.CHECKSUMS)
        github.blobs[sums_asset["id"]] = b"0" * 64 + b"  Nori-iOS-v2.6.0.ipa\n"
        with self.assertRaisesRegex(self.tool.ReleaseError, "weicht von der Prüfsumme bei GitHub ab"):
            self.tool.validate_release(github, self.meta(), ALL)
        sums_asset["digest"] = "sha256:" + hashlib.sha256(github.blobs[sums_asset["id"]]).hexdigest()
        with self.assertRaisesRegex(self.tool.ReleaseError, "weicht von checksums-sha256.txt ab"):
            self.tool.validate_release(github, self.meta(), ALL)
        ipa = next(a for a in github.release_list[0]["assets"] if a["name"] == "Nori-iOS-v2.6.0.ipa")
        github.blobs[sums_asset["id"]] = (ipa["digest"].removeprefix("sha256:") + "  Nori-iOS-v2.6.0.ipa\n"
                                          + "0" * 64 + "  Nori-macOS-v2.6.0.zip\n").encode()
        sums_asset["digest"] = "sha256:" + hashlib.sha256(github.blobs[sums_asset["id"]]).hexdigest()
        with self.assertRaisesRegex(self.tool.ReleaseError, "checksums-sha256.txt nennt"):
            self.tool.validate_release(github, self.meta(), ALL)

def workflow_run(run_id: int, path: str, created: str, status: str = "completed", sha: str = "c" * 40,
                 branch: str = "main") -> dict:
    return {"id": run_id, "path": path, "created_at": created, "status": status, "head_sha": sha,
            "head_branch": branch, "name": Path(path).stem}


class CleanupTests(ReleaseTestCase):
    CURRENT = 5000

    def setUp(self) -> None:
        super().setUp()
        self.github_fake = self.github()
        self.release(self.github_fake)
        self.github_fake.writes.clear()
        wf = ".github/workflows/"
        self.github_fake.workflow_list = [
            {"id": 1, "path": wf + "release.yml"}, {"id": 2, "path": wf + "build-ios.yml"},
            {"id": 4, "path": wf + "codeql.yml"},
            {"id": 5, "path": "dynamic/dependabot/dependabot-updates"}, {"id": 6, "path": wf + "check-sources.yml"},
        ]
        # `package-ios-ipa.yml` steht bewusst **nicht** in der Workflow-Liste:
        # GitHub nimmt einen Workflow heraus, sobald seine Datei fort ist. Seine
        # Läufe müssen trotzdem weg — sie kommen über die Liste des Repositorys.
        self.github_fake.pull_heads = {"d" * 40}
        runs = {
            1: [workflow_run(self.CURRENT, wf + "release.yml", "2026-09-17T12:00:00Z", "in_progress", self.commit),
                workflow_run(4001, wf + "release.yml", "2026-09-16T12:00:00Z", sha=self.commit),
                workflow_run(4002, wf + "release.yml", "2026-09-16T11:00:00Z", status="queued")],
            2: [workflow_run(3001, wf + "build-ios.yml", "2026-09-15T10:00:00Z"),
                workflow_run(3002, wf + "build-ios.yml", "2026-09-17T12:00:01Z"),
                workflow_run(3003, wf + "build-ios.yml", "2026-09-16T10:00:00Z", sha=self.commit),
                workflow_run(3004, wf + "build-ios.yml", "2026-09-16T10:00:00Z", sha="d" * 40, branch="claude/x"),
                workflow_run(3005, wf + "build-ios.yml", "2026-09-14T10:00:00Z", status="waiting")],
            3: [workflow_run(2001, wf + "package-ios-ipa.yml", "2026-09-13T10:00:00Z")],
            4: [workflow_run(1001, wf + "codeql.yml", "2026-09-01T10:00:00Z")],
            5: [workflow_run(1002, "dynamic/dependabot/dependabot-updates", "2026-09-01T10:00:00Z")],
            6: [workflow_run(1003, wf + "check-sources.yml", "2026-09-12T10:00:00Z", branch="claude/alt")],
        }
        self.github_fake.run_lists = runs
        self.github_fake.runs_by_id = {run["id"]: run for items in runs.values() for run in items}
        self.github_fake.artifact_lists = {
            self.CURRENT: [{"id": 71, "name": "nori-release-ios"}, {"id": 72, "name": "nori-release-windows"},
                           {"id": 73, "name": "Nori-webOS-Screenshots"}],
            3001: [{"id": 81, "name": "Nori-iOS-1.25.2-unsigned"}],
        }

    def cleanup(self, **kwargs):
        kwargs.setdefault("delay", 0)
        return self.tool.cleanup(self.github_fake, self.meta(), ALL, self.CURRENT, **kwargs)

    def test_deletes_only_old_finished_runs_of_nori_build_workflows(self) -> None:
        result = self.cleanup()
        # Älteste zuerst; 2001 gehört zu einem Workflow, den GitHub nicht mehr auflistet.
        self.assertEqual(self.github_fake.deleted_runs, [1003, 2001, 3001, 4001])
        self.assertNotIn(".github/workflows/package-ios-ipa.yml",
                         [w["path"] for w in self.github_fake.workflow_list])
        self.assertEqual(result["deleted"], 4)
        self.assertEqual(result["kept"], {
            "dieser Lauf": 1, "noch nicht abgeschlossen": 2, "nach diesem Lauf gestartet": 1,
            "Prüflauf des veröffentlichten Stands oder eines offenen Pull Requests": 2,
            # CodeQL und Dependabot werden jetzt gesehen und ausdrücklich übergangen.
            "anderer Workflow": 2,
        })
        # Nie: der laufende Lauf, fremde Workflows, Releases, Tags.
        self.assertNotIn(self.CURRENT, self.github_fake.deleted_runs)
        self.assertNotIn(1001, self.github_fake.deleted_runs)
        self.assertNotIn(1002, self.github_fake.deleted_runs)
        self.assertEqual(len(self.github_fake.release_list), 1)
        self.assertIn("v2.6.0", self.github_fake.tag_refs)
        self.assertTrue(all(w.startswith(("delete run", "delete artifact")) for w in self.github_fake.writes))

    def test_only_temporary_artifacts_of_this_run(self) -> None:
        result = self.cleanup()
        self.assertEqual(self.github_fake.deleted_artifacts, [71, 72])
        self.assertEqual(result["artifacts"], 2)

    def test_nothing_is_deleted_without_a_valid_release(self) -> None:
        self.github_fake.release_list[0]["assets"].pop()
        with self.assertRaisesRegex(self.tool.ReleaseError, "unvollständig"):
            self.cleanup()
        self.assertEqual(self.github_fake.writes, [])

    def test_nothing_is_deleted_without_the_current_run(self) -> None:
        for keep in (0, -1, None):
            with self.subTest(keep=keep):
                with self.assertRaisesRegex(self.tool.ReleaseError, "GITHUB_RUN_ID"):
                    self.tool.cleanup(self.github_fake, self.meta(), ALL, keep, delay=0)
        with self.assertRaisesRegex(self.tool.ReleaseError, "Lauf 777 nicht gefunden"):
            self.tool.cleanup(self.github_fake, self.meta(), ALL, 777, delay=0)
        self.assertEqual(self.github_fake.writes, [])

    def test_dry_run_deletes_nothing(self) -> None:
        result = self.cleanup(dry_run=True)
        self.assertEqual(result["deleted"], 4)
        self.assertEqual(self.github_fake.writes, [])

    def test_limit_and_rate_limit_stop_gracefully(self) -> None:
        result = self.cleanup(max_deletions=2)
        self.assertEqual(self.github_fake.deleted_runs, [1003, 2001])
        self.assertIn("Obergrenze", result["stopped"])
        self.assertEqual(result["left"], 2)

        self.github_fake.fail_delete[3001] = self.tool.GitHubError(403, "secondary rate limit", rate_limited=True)
        result = self.cleanup()
        self.assertIn("bremst", result["stopped"])
        self.assertNotIn(4001, self.github_fake.deleted_runs)

    def test_missing_runs_are_skipped_other_errors_fail(self) -> None:
        self.github_fake.fail_delete[2001] = self.tool.GitHubError(404, "weg")
        self.assertEqual(self.cleanup()["deleted"], 3)
        # Fehlt die Berechtigung, soll der Lauf rot werden — das ist kein Bremsen.
        self.github_fake.fail_delete[2001] = self.tool.GitHubError(403, "Resource not accessible by integration")
        with self.assertRaisesRegex(self.tool.ReleaseError, "not accessible"):
            self.cleanup()

    def test_command_insists_on_this_run(self) -> None:
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main", "GITHUB_RUN_ID": "5001"}), \
                mock.patch.object(self.tool, "github_from_environment", lambda: self.github_fake):
            code = self.tool.main(["cleanup", "--version", VERSION, "--platforms", ",".join(ALL), "--commit", self.commit,
                                   "--keep-run", str(self.CURRENT), "--delay", "0"])
        self.assertEqual(code, 1)
        self.assertEqual(self.github_fake.writes, [])

    def test_allowlist(self) -> None:
        workflows = {path.name for path in (REPO / ".github/workflows").glob("*.yml")}
        listed = {Path(path).name for path in self.tool.CLEANUP_WORKFLOWS}
        self.assertTrue({"release.yml", "build-ios.yml"} <= listed)
        # Einträge ohne Datei sind nur entfernte Nori-Workflows mit alten Läufen.
        self.assertEqual(listed - workflows, {"package-ios-ipa.yml", "package-macos-source.yml", "build-android-app.yml",
                                              "build-macos.yml", "build-webos.yml", "build-windows.yml"})
        for name in listed:
            self.assertNotRegex(name, r"codeql|dependabot|renovate|security|scan|stale|label")


class _Handler(http.server.BaseHTTPRequestHandler):
    def _handle(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        path = self.path.split("?")[0]
        self.server.seen.append((self.command, path, self.headers.get("Authorization"), body))
        answer = self.server.routes.get((self.command, path), (404, {}, b'{"message": "Not Found"}'))
        # Eine Liste beantwortet jeden Aufruf anders — für die Wiederholungen.
        if isinstance(answer, list):
            answer = answer.pop(0) if len(answer) > 1 else answer[0]
        status, headers, payload = answer
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_PATCH = do_DELETE = _handle

    def log_message(self, *args) -> None:
        pass


class GitHubRequestTests(unittest.TestCase):
    TOKEN = "fake-" + "token-value-for-tests"

    def setUp(self) -> None:
        self.tool = load_tool()
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        self.server.routes = {}
        self.server.seen = []
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.github = self.tool.GitHub("owner/nori", self.TOKEN, api=self.base, uploads=self.base, opener=opener)
        self.tool.RETRY_PAUSE = 0

    def route(self, method: str, path: str, status: int = 200, payload: object = None, headers=None, raw: bytes | None = None):
        body = raw if raw is not None else json.dumps(payload if payload is not None else {}).encode()
        self.server.routes[(method, path)] = (status, headers or {}, body)

    def routes(self, method: str, path: str, answers: list[tuple[int, object]]) -> None:
        """Mehrere Antworten hintereinander: (Status, Nutzlast)."""
        self.server.routes[(method, path)] = [(status, {}, json.dumps(payload).encode()) for status, payload in answers]

    def test_missing_tag_and_annotated_tag(self) -> None:
        self.assertIsNone(self.github.tag_commit("v2.6.0"))
        self.route("GET", "/repos/owner/nori/git/ref/tags/v2.6.0",
                   payload={"ref": "refs/tags/v2.6.0", "object": {"type": "tag", "sha": "t" * 40}})
        self.route("GET", f"/repos/owner/nori/git/tags/{'t' * 40}", payload={"object": {"type": "commit", "sha": "c" * 40}})
        self.assertEqual(self.github.tag_commit("v2.6.0"), "c" * 40)

    def test_existing_tag_reference_fails_with_422(self) -> None:
        self.route("POST", "/repos/owner/nori/git/tags", 201, {"sha": "t" * 40})
        self.route("POST", "/repos/owner/nori/git/refs", 422, {"message": "Reference already exists"})
        with self.assertRaises(self.tool.GitHubError) as caught:
            self.github.create_tag("v2.6.0", "c" * 40, "Nori v2.6.0")
        self.assertEqual(caught.exception.status, 422)
        self.assertNotIn(self.TOKEN, str(caught.exception))

    def test_token_is_not_forwarded_on_redirects(self) -> None:
        self.route("GET", "/repos/owner/nori/releases/assets/5", 302, headers={"Location": f"{self.base}/blob"})
        self.route("GET", "/blob", raw=b"inhalt")
        self.assertEqual(self.github.download_asset({"id": 5}), b"inhalt")
        authorization = {path: header for _, path, header, _ in self.server.seen}
        self.assertEqual(authorization["/repos/owner/nori/releases/assets/5"], f"Bearer {self.TOKEN}")
        self.assertIsNone(authorization["/blob"])

    def test_errors_do_not_contain_the_token(self) -> None:
        self.route("GET", "/repos/owner/nori/releases/tags/v2.6.0", 500, {"message": "boom"})
        with self.assertRaises(self.tool.GitHubError) as caught:
            self.github.release_by_tag("v2.6.0")
        self.assertIn("HTTP 500 boom", str(caught.exception))
        self.assertNotIn(self.TOKEN, str(caught.exception))
        self.assertNotIn(self.TOKEN, repr(self.github))

    def test_https_always_verifies_certificates(self) -> None:
        context = self.tool.https_context()
        self.assertEqual(context.verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(context.check_hostname)

    def test_commit_on_main(self) -> None:
        self.route("GET", f"/repos/owner/nori/compare/main...{'c' * 40}", payload={"status": "behind", "ahead_by": 0})
        self.assertTrue(self.github.on_main("c" * 40))
        self.route("GET", f"/repos/owner/nori/compare/main...{'d' * 40}", payload={"status": "diverged", "ahead_by": 2})
        self.assertFalse(self.github.on_main("d" * 40))

    def test_only_runs_and_artifacts_can_be_deleted(self) -> None:
        self.route("DELETE", "/repos/owner/nori/actions/runs/42", 204, raw=b"")
        self.route("DELETE", "/repos/owner/nori/actions/artifacts/7", 204, raw=b"")
        self.github.delete_run(42)
        self.github.delete_artifact(7)
        for path in ("/releases/1", "/releases/assets/1", "/git/refs/tags/v2.6.0", "/git/refs/heads/main",
                     "/actions/workflows/1", "/actions/runs/42/logs", "/actions/runs/0", "/contents/README.md", ""):
            with self.subTest(path=path):
                with self.assertRaisesRegex(self.tool.ReleaseError, "nur für Workflow-Läufe und -Artefakte"):
                    self.github.request("DELETE", path)
        with self.assertRaisesRegex(self.tool.ReleaseError, "nur für Workflow-Läufe"):
            self.github.request("DELETE", "https://api.github.com/repos/owner/nori/releases/1")
        self.assertEqual([(m, p) for m, p, *_ in self.server.seen],
                         [("DELETE", "/repos/owner/nori/actions/runs/42"), ("DELETE", "/repos/owner/nori/actions/artifacts/7")])

    def test_rate_limit_is_recognised(self) -> None:
        self.route("DELETE", "/repos/owner/nori/actions/runs/43", 403,
                   {"message": "You have exceeded a secondary rate limit"})
        self.route("DELETE", "/repos/owner/nori/actions/runs/44", 403, {"message": "Forbidden"},
                   headers={"x-ratelimit-remaining": "0"})
        self.route("DELETE", "/repos/owner/nori/actions/runs/45", 403, {"message": "Resource not accessible by integration"})
        for run_id, limited in ((43, True), (44, True), (45, False)):
            with self.subTest(run=run_id):
                with self.assertRaises(self.tool.GitHubError) as caught:
                    self.github.delete_run(run_id)
                self.assertEqual(caught.exception.rate_limited, limited)

    def test_reads_are_retried_writes_are_not(self) -> None:
        # Lesen: erst 500, dann 502, dann die Antwort — der Aufruf gelingt.
        self.routes("GET", "/repos/owner/nori/releases/tags/v2.6.0",
                    [(500, {"message": "boom"}), (502, {"message": "bad gateway"}), (200, {"id": 7, "draft": False})])
        self.assertEqual(self.github.release_by_tag("v2.6.0")["id"], 7)
        self.assertEqual(len([1 for method, path, *_ in self.server.seen if path.endswith("v2.6.0")]), 3)

        # Schreiben: ein Versuch. Ein zweites POST könnte einen zweiten Entwurf anlegen.
        self.server.seen.clear()
        self.route("POST", "/repos/owner/nori/releases", 500, {"message": "boom"})
        with self.assertRaises(self.tool.GitHubError):
            self.github.create_draft(self.tool.Meta("2.6.0", "c" * 40, {}, {}), "Notes")
        self.assertEqual(len(self.server.seen), 1)

        # Eine klare Antwort wird nicht wiederholt, auch nicht beim Lesen.
        self.server.seen.clear()
        self.route("GET", "/repos/owner/nori/actions/runs/9", 422, {"message": "nope"})
        with self.assertRaises(self.tool.GitHubError):
            self.github.run(9)
        self.assertEqual(len(self.server.seen), 1)

    def test_transient_read_errors_give_up_after_three_tries(self) -> None:
        self.route("GET", "/repos/owner/nori/releases/tags/v2.6.0", 503, {"message": "unavailable"})
        with self.assertRaises(self.tool.GitHubError) as caught:
            self.github.release_by_tag("v2.6.0")
        self.assertEqual(caught.exception.status, 503)
        self.assertEqual(len(self.server.seen), self.tool.RETRIES)

    def test_paging(self) -> None:
        self.route("GET", "/repos/owner/nori/actions/workflows/9/runs",
                   payload={"total_count": 1, "workflow_runs": [{"id": 1}]})
        self.assertEqual(self.github.workflow_runs(9), [{"id": 1}])
        self.route("GET", "/repos/owner/nori/pulls", payload=[{"head": {"sha": "e" * 40}}])
        self.assertEqual(self.github.open_pull_heads(), {"e" * 40})


def load_workflow(name: str) -> dict:
    ruby = shutil.which("ruby")
    if ruby is None:
        raise unittest.SkipTest("ruby fehlt – Workflow-Struktur nicht prüfbar")
    result = subprocess.run(
        [ruby, "-ryaml", "-rjson", "-e", "puts JSON.generate(YAML.load(File.read(ARGV[0])))",
         str(REPO / ".github/workflows" / name)],
        capture_output=True, text=True, check=True,
    )
    return json.loads(result.stdout)


def triggers(workflow: dict) -> dict:
    # YAML 1.1 liest den Schlüssel `on` als Wahrheitswert.
    return workflow.get("on") or workflow.get("true") or {}


def all_steps(workflow: dict) -> list[dict]:
    return [step for job in workflow["jobs"].values() for step in job.get("steps", [])]


BUILD_WORKFLOWS = {"ios": "build-ios.yml"}


class WorkflowTests(unittest.TestCase):
    def test_jobs_use_github_hosted_runners(self) -> None:
        # Der eigene Mac ist offline. Kein Job darf auf [self-hosted, …] warten.
        # Ohne ruby: die runs-on-Zeilen selbst, nicht der geparste Baum.
        hosted = ("ubuntu-latest", "macos-26", "windows-latest")
        for path in sorted((REPO / ".github/workflows").glob("*.yml")):
            text = path.read_text()
            self.assertNotRegex(
                text,
                r"(?m)^\s+runs-on:\s*\[?\s*self-hosted",
                f"{path.name} wartet auf einen self-hosted Runner",
            )
            for match in re.finditer(r"(?m)^\s+runs-on:\s*(.+)$", text):
                value = match.group(1).strip()
                if "NORI_WINDOWS_RUNNER" in value:
                    self.assertIn("windows-latest", value)
                    self.assertNotIn("self-hosted", value)
                    continue
                self.assertTrue(
                    any(label == value or f'"{label}"' == value or f"'{label}'" == value
                        for label in hosted),
                    f"{path.name}: unexpected runs-on {value!r}",
                )

    def test_release_is_only_started_by_hand(self) -> None:
        on = triggers(load_workflow("release.yml"))
        self.assertEqual(set(on), {"workflow_dispatch"})
        inputs = on["workflow_dispatch"]["inputs"]
        # Nur noch eine Plattform: nichts abzuwählen.
        self.assertEqual(set(inputs), {"version", "dry_run"})
        self.assertTrue(inputs["version"]["required"])
        self.assertEqual(inputs["version"]["type"], "string")
        self.assertIs(inputs["dry_run"]["default"], False)

    def test_one_release_at_a_time(self) -> None:
        workflow = load_workflow("release.yml")
        self.assertEqual(workflow["concurrency"], {"group": "nori-release", "cancel-in-progress": False})

    def test_release_job_graph(self) -> None:
        jobs = load_workflow("release.yml")["jobs"]
        self.assertEqual(set(jobs), {"prepare", "checks", *BUILD_WORKFLOWS, "publish", "validate", "cleanup"})
        self.assertEqual(jobs["checks"]["needs"], "prepare")
        for platform, file in BUILD_WORKFLOWS.items():
            job = jobs[platform]
            self.assertEqual(job["uses"], f"./.github/workflows/{file}")
            self.assertEqual(sorted(job["needs"]), ["checks", "prepare"])
            self.assertNotIn("if", job)
            self.assertEqual(job["with"]["release-version"], "${{ needs.prepare.outputs.version }}")
            self.assertEqual(job["permissions"], {"contents": "read"})
        publish = jobs["publish"]
        self.assertEqual(sorted(publish["needs"]), sorted(["prepare", "checks", *BUILD_WORKFLOWS]))
        condition = publish["if"]
        self.assertIn("!cancelled()", condition)
        self.assertIn("needs.prepare.result == 'success'", condition)
        self.assertIn("needs.checks.result == 'success'", condition)
        for platform in BUILD_WORKFLOWS:
            self.assertIn(f"needs.{platform}.result == 'success'", condition)
        for bypass in ("always()", "failure()", "|| true"):
            self.assertNotIn(bypass, condition)
        validate, cleanup = jobs["validate"], jobs["cleanup"]
        self.assertEqual(sorted(validate["needs"]), ["prepare", "publish"])
        self.assertIn("needs.publish.result == 'success'", validate["if"])
        self.assertIn("needs.prepare.outputs.dry_run != 'true'", validate["if"])
        self.assertEqual(sorted(cleanup["needs"]), ["prepare", "publish", "validate"])
        for required in ("needs.validate.result == 'success'", "needs.publish.result == 'success'",
                         "needs.prepare.outputs.dry_run != 'true'"):
            self.assertIn(required, cleanup["if"])

    def test_release_permissions_are_minimal(self) -> None:
        workflow = load_workflow("release.yml")
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        jobs = workflow["jobs"]
        self.assertEqual(jobs["publish"]["permissions"], {"contents": "write"})
        self.assertEqual(jobs["cleanup"]["permissions"], {"actions": "write", "contents": "read", "pull-requests": "read"})
        for name in ("prepare", "checks", "validate"):
            self.assertEqual(jobs[name]["permissions"], {"contents": "read"}, name)
        for path in sorted((REPO / ".github/workflows").glob("*.yml")):
            with self.subTest(workflow=path.name):
                self.assertNotIn("write-all", path.read_text())
                workflow = load_workflow(path.name)
                writes = [workflow.get("permissions", {})] + [job.get("permissions", {}) for job in workflow["jobs"].values()]
                for permissions in writes:
                    if isinstance(permissions, dict):
                        granted = {k for k, v in permissions.items() if v == "write"}
                        if path.name != "release.yml":
                            self.assertEqual(granted, set(), path.name)

    def test_release_steps(self) -> None:
        jobs = load_workflow("release.yml")["jobs"]
        runs = "\n".join(step.get("run", "") for step in all_steps({"jobs": jobs}))
        for forbidden in ("gh release", "curl ", "git push", "git tag", "--force", "${{ inputs.version }}",
                          "${{ github.event.inputs"):
            self.assertNotIn(forbidden, runs)
        prepare = "\n".join(step.get("run", "") for step in jobs["prepare"]["steps"])
        self.assertIn('--version "$VERSION_INPUT"', prepare)
        publish = next(step for step in jobs["publish"]["steps"] if "nori-release.py publish" in step.get("run", ""))
        self.assertIn('--commit "$GITHUB_SHA"', publish["run"])
        self.assertIn("--sha256", publish["run"])
        self.assertIn("ios=$SHA256_IOS", publish["run"])
        cleanup = next(step for step in jobs["cleanup"]["steps"] if "nori-release.py cleanup" in step.get("run", ""))
        self.assertIn('--keep-run "$GITHUB_RUN_ID"', cleanup["run"])
        for name in ("publish", "validate", "cleanup"):
            checkout = next(step for step in jobs[name]["steps"] if str(step.get("uses", "")).startswith("actions/checkout"))
            self.assertFalse(checkout["with"]["persist-credentials"], name)
        download = next(step for step in jobs["publish"]["steps"] if str(step.get("uses", "")).startswith("actions/download-artifact"))
        self.assertEqual(download["with"]["pattern"], "nori-release-*")
        self.assertIs(download["with"]["merge-multiple"], True)
        self.assertFalse(any("upload-artifact" in str(step.get("uses", "")) for step in all_steps({"jobs": jobs})))

    def test_build_workflows_can_be_called_by_the_release(self) -> None:
        for platform, file in BUILD_WORKFLOWS.items():
            with self.subTest(workflow=file):
                workflow = load_workflow(file)
                call = triggers(workflow)["workflow_call"]
                self.assertTrue(call["inputs"]["release-version"]["required"])
                outputs = call["outputs"]
                self.assertIn("sha256", outputs)
                group = workflow["concurrency"]["group"]
                self.assertIn("inputs.release-version", group)
                self.assertIn("github.run_id", group)
                self.assertIn("!inputs.release-version", str(workflow["concurrency"]["cancel-in-progress"]))

    def test_packages_are_verified_before_upload(self) -> None:
        for platform, file in BUILD_WORKFLOWS.items():
            with self.subTest(workflow=file):
                workflow = load_workflow(file)
                for job_name, job in workflow["jobs"].items():
                    self.assertNotIn("continue-on-error", job)
                    steps = job.get("steps", [])
                    names = [step.get("name") for step in steps]
                    for step in steps:
                        if step.get("continue-on-error"):
                            # Erlaubt nur beim **Hochladen** und nur an einem Schritt,
                            # der im Release nicht läuft: Ein Testpaket darf am vollen
                            # Artefakt-Speicher scheitern, ein Release nie — und eine
                            # Prüfung nie. Ohne die erste Bedingung hätte auch der
                            # Fernbedienungslauf optional werden können, mit seinen 341
                            # Prüfungen; nachgestellt, die Reihe blieb grün.
                            where = f"{file}/{job_name}/{step.get('name')}"
                            self.assertIn("upload-artifact", str(step.get("uses", "")), where)
                            self.assertIn("!inputs.release-version", str(step.get("if", "")), where)
                        if "upload-artifact" in str(step.get("uses", "")):
                            self.assertIn("retention-days", step["with"], f"{job_name}/{step.get('name')}")
                    uploads = [i for i, step in enumerate(steps)
                               if "upload-artifact" in str(step.get("uses", ""))
                               and "failure()" not in str(step.get("if", ""))
                               and not step.get("continue-on-error")]
                    if not uploads:
                        continue
                    checks = [i for i, step in enumerate(steps) if "tools/nori-release.py verify" in step.get("run", "")]
                    self.assertTrue(checks, f"{file}/{job_name}: kein Prüfschritt vor dem Hochladen")
                    self.assertLess(max(checks), min(uploads), f"{file}/{job_name}")
                    upload = steps[uploads[0]]
                    self.assertIn("steps.meta.outputs.artifact", upload["with"]["name"])
                    self.assertIn("steps.meta.outputs.retention", str(upload["with"]["retention-days"]))
                    self.assertIs(upload["with"]["overwrite"], True)
                    self.assertEqual(upload["with"]["if-no-files-found"], "error")
                    self.assertLess(names.index("Version prüfen"), uploads[0])

    def test_the_release_upload_is_never_optional(self) -> None:
        for platform, file in BUILD_WORKFLOWS.items():
            with self.subTest(workflow=file):
                for job in load_workflow(file)["jobs"].values():
                    for step in job.get("steps", []):
                        if "upload-artifact" not in str(step.get("uses", "")):
                            continue
                        condition, optional = str(step.get("if", "")), bool(step.get("continue-on-error"))
                        release = "!inputs.release-version" not in condition and "failure()" not in condition
                        # Was im Release hochlädt, muss gelingen.
                        self.assertFalse(release and optional, f"{file}: {step.get('name')}")

    def test_temporary_artifacts_are_short_lived(self) -> None:
        for path in sorted((REPO / ".github/workflows").glob("*.yml")):
            for step in all_steps(load_workflow(path.name)):
                if "upload-artifact" in str(step.get("uses", "")):
                    with self.subTest(workflow=path.name, step=step.get("name")):
                        days = step["with"].get("retention-days")
                        self.assertIsNotNone(days)
                        if isinstance(days, int):
                            self.assertLessEqual(days, 3)

    def test_platform_production_checks_stay(self) -> None:
        ios = {step.get("name"): step for step in load_workflow("build-ios.yml")["jobs"]["ipa"]["steps"]}
        self.assertIn("--ios", ios["Google OAuth für iOS bereitstellen"]["run"])
        self.assertIn("--verify-ios-app", ios["Google OAuth im gebauten Programm prüfen"]["run"])
        self.assertIn("--verify-ios-ipa", ios["Google OAuth in der fertigen IPA prüfen"]["run"])
        self.assertIn("check-app --platform ios", ios["Version im gebauten Programm prüfen"]["run"])

    def test_tags_start_no_workflow(self) -> None:
        # Ein Release-Tag darf weder Builds noch einen zweiten Release anstoßen.
        for path in sorted((REPO / ".github/workflows").glob("*.yml")):
            with self.subTest(workflow=path.name):
                on = triggers(load_workflow(path.name))
                self.assertNotIn("release", on)
                push = on.get("push")
                if push is None:
                    continue
                self.assertIsInstance(push, dict)
                self.assertTrue(push.get("branches"), "push ohne Branch-Filter läuft auch für Tags")
                self.assertNotIn("tags", push)

    def test_replaced_workflows_are_gone(self) -> None:
        for name in ("package-ios-ipa.yml", "package-macos-source.yml",
                     "build-macos.yml", "build-webos.yml", "build-windows.yml"):
            self.assertFalse((REPO / ".github/workflows" / name).exists(), name)
        for path in sorted((REPO / ".github/workflows").glob("*.yml")):
            text = path.read_text()
            self.assertNotIn("package-ios-ipa.yml", text, path.name)
            self.assertNotIn("package-macos-source.yml", text, path.name)
            self.assertNotRegex(text, r"(ios|macos|webos|windows)-v\$|(ios|macos|webos|windows)-v\*", path.name)


class CurrentRepositoryTests(unittest.TestCase):
    """Der aktuelle Stand hat eine gemeinsame Version und öffentliche Notes."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.tool.SECRETS_DIR = Path(self.temp.name) / "keine-secrets"

    def test_current_version_has_public_release_notes(self) -> None:
        meta = self.tool.read_meta("HEAD")
        notes = self.tool.build_notes(meta, list(self.tool.PLATFORMS), "owner/nori")
        self.assertIn(f"**Nori {meta.version}**", notes)
        self.assertIsNone(self.tool.SENSITIVE.search(notes))
        for spec in self.tool.ASSETS.values():
            self.assertIn(spec.name(meta.version), notes)


if __name__ == "__main__":
    unittest.main()
