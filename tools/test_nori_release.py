#!/usr/bin/env python3
"""Regressionstests für tools/nori-release.py — ohne echte Releases und ohne echte Tags.

GitHub ist durch einen Nachbau im Speicher ersetzt (`FakeGitHub`), das
Repository durch ein Wegwerf-Repository im Temp-Ordner. Pakete, Client-IDs,
Secrets und Tokens sind erfunden und werden zur Laufzeit zusammengesetzt, damit
keine Prüfung des Repositorys sie für echte hält. Kein Test liest
`~/.config/nori/secrets`.

Nur `GitHubRequestTests` spricht HTTP — mit einem lokalen Server auf 127.0.0.1.
`WorkflowTests` und `CurrentRepositoryTests` lesen die echten Workflows und den
echten Changelog, schreiben aber nichts.

    python3 tools/test_nori_release.py
"""

from __future__ import annotations

import contextlib
import hashlib
import http.server
import importlib.util
import io
import json
import plistlib
import shutil
import ssl
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
import urllib.request
import zipfile
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "nori-release.py"
REPO = Path(__file__).resolve().parent.parent
SUFFIX = ".apps.googleusercontent.com"
SECRET_PREFIX = "GOCSPX" + "-"

IOS_ID = "222222222222-" + "iosclien" * 4 + SUFFIX
MAC_ID = "333333333333-" + "macclien" * 4 + SUFFIX
MAC_SECRET = SECRET_PREFIX + "macSecretFake" + "M" * 16
TV_ID = "111111111111-" + "tvclient" * 4 + SUFFIX
TV_SECRET = SECRET_PREFIX + "tvSecretFake" + "T" * 16
OLD_TV_ID = "444444444444-" + "oldtvcli" * 4 + SUFFIX
OLD_TV_SECRET = SECRET_PREFIX + "oldTvSecret" + "Q" * 16
ACCESS_TOKEN = "ya" + "29." + "a" * 32
REFRESH_TOKEN = "1/" + "/0" + "r" * 32
OTHER_COMMIT = "b" * 40

CHANGELOG = """# Changelog

## [webOS 2.2.1] — 2026-09-13

Nur ein Paketierungsfehler. Kein App-Code geändert; OAuth-Fluss und Scope
unverändert. iOS und macOS unverändert.

### Behoben

- **Das installierbare Paket hatte keinen Google-Zugang.** Der Workflow baute
  ohne `VITE_NORI_GOOGLE_TV_CLIENT_ID` aus der `.env.local`.
- Jetzt schreibt der Runner die Zugangsdaten aus `~/.config/nori/secrets`.
- Die Liste lädt schneller.

### Tests

- 22 neue Tests.

## [iOS 1.25.2] · [macOS 1.20.1] — 2026-09-13

Abschließende Apple-Prüfung, z. B. Player auf iPad und Mac. Keine Änderung an OAuth.

### Behoben — macOS

- **Das Öffnen einer Folge brachte Nori zum Absturz.** Der Player benutzt jetzt AVPlayerView.

### Behoben — beide Apple-Apps

- **Nach dem Countdown startete die nächste Folge nicht.**
  Die neue Folge startet jetzt in einer eigenen Aufgabe.
  - Unterpunkt ohne Einzelheiten.
  - Unterpunkt über den Refresh-Token.

### Behoben — iOS/iPadOS

- **Menüs der unteren Leiste standen auf dem Kopf.**

```bash
python3 tools/configure-google-oauth.py --ios
```

### Geprüft, ohne Änderung

- Bild-Cache unter Last.
"""


def load_tool():
    spec = importlib.util.spec_from_file_location("nori_release", TOOL)
    module = importlib.util.module_from_spec(spec)
    # Dataclasses schlagen ihr Modul in sys.modules nach.
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


def make_repo(root: Path) -> str:
    files = {
        "native/Nori-iOS/Nori.xcodeproj/project.pbxproj": pbxproj("1.25.2", "39", "to.nori.ios"),
        "native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj": pbxproj("1.20.1", "30", "to.nori.macos"),
        "native/Nori-macOS/Nori/NoriApp.swift": "@main struct NoriApp {}\n",
        "native/Nori-macOS/Config/Google.local.xcconfig.example": "GOOGLE_CLIENT_ID = <aus der OAuth-JSON>\n",
        "native/NoriCore/Sources/NoriCore/Models.swift": "struct Models {}\n",
        "native/Package.swift": "// swift-tools-version:5.9\n",
        "native/Tests/NoriCoreTests/ModelsTests.swift": f"let fake = \"{ACCESS_TOKEN}\"\n",
        "config/contract.json": "{}\n",
        "README.md": "# Nori\n",
        "CHANGELOG.md": CHANGELOG,
        "apps/webos/appinfo.json": json.dumps({"id": "tv.nori.app", "version": "2.2.1"}) + "\n",
    }
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    (root / "native/Nori-macOS/Nori/Models.swift").symlink_to("../../NoriCore/Sources/NoriCore/Models.swift")
    subprocess.run(["git", "-c", "init.defaultBranch=main", "init", "-q", str(root)], check=True)
    git(root, "add", "-A")
    git(root, "commit", "-qm", "Stand")
    return git(root, "rev-parse", "HEAD")


def make_secrets(directory: Path) -> None:
    directory.mkdir()
    (directory / "google-webos-oauth.json").write_text(json.dumps({"installed": {"client_id": TV_ID, "client_secret": TV_SECRET}}))
    (directory / "google-webos-oauth-test.json").write_text(json.dumps({"installed": {"client_id": OLD_TV_ID, "client_secret": OLD_TV_SECRET}}))
    (directory / "google-macos-oauth.json").write_text(json.dumps({"installed": {"client_id": MAC_ID, "client_secret": MAC_SECRET}}))
    (directory / "google-ios-client-id").write_text(IOS_ID + "\n")


def make_ipa(directory: Path, version: str = "1.25.2", build: str = "39", bundle: str = "to.nori.ios",
             name: str | None = None, extra: dict[str, bytes] | None = None, apps: tuple[str, ...] = ("Nori.app",)) -> Path:
    path = directory / (name or f"Nori-iOS-{version}-unsigned.ipa")
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


def targz(entries: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
        for name, data in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    return buffer.getvalue()


def make_ipk(directory: Path, version: str = "2.2.1", name: str | None = None, control_version: str | None = None,
             appinfo_version: str | None = None, extra: dict[str, bytes] | None = None, raw: bytes | None = None) -> Path:
    path = directory / (name or f"tv.nori.app_{version}_all.ipk")
    if raw is not None:
        path.write_bytes(raw)
        return path
    control = targz({"./control": f"Package: tv.nori.app\nVersion: {control_version or version}\nArchitecture: all\n".encode()})
    data = {
        "./usr/palm/applications/tv.nori.app/appinfo.json":
            json.dumps({"id": "tv.nori.app", "version": appinfo_version or version}).encode(),
        "./usr/palm/applications/tv.nori.app/index.html": b"<!doctype html>",
        "./usr/palm/applications/tv.nori.app/assets/index-abcdefgh.js":
            ("var e={clientId:" + json.dumps(TV_ID) + ",clientSecret:" + json.dumps(TV_SECRET) + "};").encode(),
    }
    data.update(extra or {})
    content = b"!<arch>\n"
    for member, blob in (("debian-binary", b"2.0\n"), ("control.tar.gz", control), ("data.tar.gz", targz(data))):
        content += f"{member + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(blob):<10}`\n".encode() + blob
        if len(blob) % 2:
            content += b"\n"
    path.write_bytes(content)
    return path


class FakeGitHub:
    """GitHub im Speicher. `writes` hält fest, was ein echter Lauf verändert hätte."""

    def __init__(self, tool, main_commits=(), tags=None, releases=None):
        self.tool = tool
        self.main_commits = set(main_commits)
        self.tag_refs: dict[str, str] = dict(tags or {})
        self.release_list: list[dict] = [dict(release) for release in (releases or [])]
        self.writes: list[str] = []
        self.downloads: list[int] = []
        self.corrupt_upload = False
        self.tag_race = False
        self.runs: dict[str, dict] = {}
        self.job_lists: dict[str, list] = {}
        self.artifact_lists: dict[str, list] = {}
        self.artifact_files: dict[int, Path] = {}
        self.latest: dict[str, dict] = {}

    def find(self, release_id):
        return next(release for release in self.release_list if release["id"] == release_id)

    def tag_commit(self, tag):
        return self.tag_refs.get(tag)

    def tags(self, prefix):
        return [tag for tag in self.tag_refs if tag.startswith(prefix)]

    def releases(self):
        return [dict(release) for release in self.release_list]

    def on_main(self, commit):
        return commit in self.main_commits

    def create_draft(self, meta, notes):
        self.writes.append("draft")
        release = {"id": len(self.release_list) + 1, "tag_name": meta.tag, "name": meta.title, "body": notes,
                   "draft": True, "assets": [], "target_commitish": meta.commit}
        self.release_list.append(release)
        return dict(release)

    def upload(self, release, path, name, content_type):
        self.writes.append("upload")
        data = path.read_bytes()
        if self.corrupt_upload:
            data = data[::-1]
        asset = {"id": 100 + release["id"], "name": name, "size": path.stat().st_size, "state": "uploaded",
                 "digest": "sha256:" + hashlib.sha256(data).hexdigest(), "content_type": content_type}
        self.find(release["id"])["assets"].append(asset)
        return asset

    def assets(self, release):
        return list(self.find(release["id"])["assets"])

    def download_asset(self, asset):
        raise AssertionError("Der Nachbau liefert immer eine Prüfsumme")

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

    def run(self, run_id):
        return self.runs[run_id]

    def jobs(self, run_id):
        return self.job_lists[run_id]

    def latest_successful_run(self, workflow):
        return self.latest.get(workflow)

    def artifacts(self, run_id):
        return self.artifact_lists[run_id]

    def download_artifact(self, artifact, destination):
        self.downloads.append(artifact["id"])
        shutil.copy(self.artifact_files[artifact["id"]], destination)


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
        self.tool.production_check = lambda meta, path: self.production_calls.append(path.name)
        self.out = self.temp / "out"
        self.out.mkdir()
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

    def meta(self, key: str):
        return self.tool.read_meta(key, "HEAD")

    def commit_file(self, name: str, text: str) -> None:
        (self.repo / name).write_text(text, encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "Änderung")
        self.commit = git(self.repo, "rev-parse", "HEAD")

    def source_zip(self, name: str = "Nori-macOS-1.20.1-source.zip", exclude: tuple[str, ...] = ()) -> Path:
        path = self.out / name
        path.unlink(missing_ok=True)  # zip ergänzt sonst ein vorhandenes Archiv
        command = ["zip", "-r", "-y", "-q", str(path), *self.tool.SOURCE_PATHS["macos"]]
        if exclude:
            command += ["-x", *exclude]
        subprocess.run(command, cwd=self.repo, check=True)
        return path

    def github(self, **kwargs) -> FakeGitHub:
        kwargs.setdefault("main_commits", {self.commit})
        return FakeGitHub(self.tool, **kwargs)

    def release(self, key: str, asset: Path, github: FakeGitHub, sha256: str | None = None, dry_run: bool = False):
        digest = sha256 if sha256 is not None else hashlib.sha256(asset.read_bytes()).hexdigest()
        return self.tool.run_release(self.meta(key), lambda: asset, github, digest, "owner/nori", dry_run)


class MetaTests(ReleaseTestCase):
    def test_versions_tags_and_assets_come_from_the_commit(self) -> None:
        ios, macos, webos = self.meta("ios"), self.meta("macos"), self.meta("webos")
        self.assertEqual((ios.version, ios.build, ios.commit), ("1.25.2", "39", self.commit))
        self.assertEqual((ios.tag, ios.title, ios.asset), ("ios-v1.25.2", "Nori iOS 1.25.2", "Nori-iOS-1.25.2-unsigned.ipa"))
        self.assertEqual((macos.tag, macos.title, macos.asset), ("macos-v1.20.1", "Nori macOS 1.20.1", "Nori-macOS-1.20.1-source.zip"))
        self.assertEqual((webos.tag, webos.title, webos.asset), ("webos-v2.2.1", "Nori webOS 2.2.1", "tv.nori.app_2.2.1_all.ipk"))
        self.assertIsNone(webos.build)

    def test_invalid_version_is_an_error(self) -> None:
        for bad in ("1.25", "1.25.2-beta", "v1.25.2", "01.25.2", "1.25.2.1", ""):
            with self.subTest(version=bad):
                self.commit_file("native/Nori-iOS/Nori.xcodeproj/project.pbxproj", pbxproj(bad, "39", "to.nori.ios"))
                with self.assertRaisesRegex(self.tool.ReleaseError, "Ungültige Versionsnummer"):
                    self.meta("ios")

    def test_invalid_webos_version_is_an_error(self) -> None:
        self.commit_file("apps/webos/appinfo.json", json.dumps({"id": "tv.nori.app", "version": "2.2"}))
        with self.assertRaisesRegex(self.tool.ReleaseError, "Ungültige Versionsnummer"):
            self.meta("webos")

    def test_inconsistent_marketing_version_is_an_error(self) -> None:
        self.commit_file("native/Nori-iOS/Nori.xcodeproj/project.pbxproj", pbxproj("1.25.2", "39", "to.nori.ios", "1.25.3"))
        with self.assertRaisesRegex(self.tool.ReleaseError, "uneinheitlich"):
            self.meta("ios")

    def test_invalid_build_number_is_an_error(self) -> None:
        self.commit_file("native/Nori-macOS/NoriMac.xcodeproj/project.pbxproj", pbxproj("1.20.1", "30a", "to.nori.macos"))
        with self.assertRaisesRegex(self.tool.ReleaseError, "Buildnummer"):
            self.meta("macos")


class DecisionTests(ReleaseTestCase):
    def decide(self, tag_commit=None, releases=(), tags=()):
        return self.tool.decide(self.meta("ios"), tag_commit, list(releases), list(tags))

    def test_new_version_is_created(self) -> None:
        self.assertEqual(self.decide(tags=["ios-v1.25.1"]).action, "create")

    def test_existing_release_is_skipped(self) -> None:
        release = {"tag_name": "ios-v1.25.2", "draft": False}
        self.assertEqual(self.decide(self.commit, [release]).action, "skip")
        # Auch wenn ein späterer main-Commit dieselbe Version trägt: kein zweiter Release.
        self.assertEqual(self.decide(OTHER_COMMIT, [release]).action, "skip")

    def test_existing_tag_without_release_is_not_released(self) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, "ohne Release"):
            self.decide(self.commit)

    def test_tag_on_other_commit_is_an_error(self) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, "zeigt auf bbbbbbb"):
            self.decide(OTHER_COMMIT)

    def test_leftover_draft_is_an_error(self) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, "Entwurf"):
            self.decide(None, [{"tag_name": "ios-v1.25.2", "draft": True}])

    def test_older_version_than_existing_is_an_error(self) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, "älter als das vorhandene ios-v1.26.0"):
            self.decide(tags=["ios-v1.9.4", "ios-v1.26.0", "macos-v9.0.0"])


class PublishTests(ReleaseTestCase):
    def test_new_version_creates_exactly_one_release(self) -> None:
        github = self.github(tags={"ios-v1.9.4": OTHER_COMMIT})
        asset = make_ipa(self.out)
        self.assertEqual(self.release("ios", asset, github), "created")
        self.assertEqual(github.writes, ["draft", "upload", "tag", "publish"])
        self.assertEqual(github.tag_refs["ios-v1.25.2"], self.commit)
        [release] = [r for r in github.release_list if r["tag_name"] == "ios-v1.25.2"]
        self.assertFalse(release["draft"])
        self.assertEqual(release["name"], "Nori iOS 1.25.2")
        self.assertEqual([a["name"] for a in release["assets"]], ["Nori-iOS-1.25.2-unsigned.ipa"])
        self.assertIn("Unsigned IPA – muss vor der Installation mit einer gültigen Signatur signiert werden.", release["body"])
        self.assertIn("**Build:** 39", release["body"])
        self.assertIn(self.commit[:7], release["body"])
        self.assertEqual(self.production_calls, ["Nori-iOS-1.25.2-unsigned.ipa"])

    def test_webos_and_macos_release_their_own_packages(self) -> None:
        github = self.github()
        self.assertEqual(self.release("webos", make_ipk(self.out), github), "created")
        self.assertEqual(self.release("macos", self.source_zip(), github), "created")
        self.assertEqual(sorted(github.tag_refs), ["macos-v1.20.1", "webos-v2.2.1"])
        assets = {r["tag_name"]: [a["name"] for a in r["assets"]] for r in github.release_list}
        self.assertEqual(assets, {"webos-v2.2.1": ["tv.nori.app_2.2.1_all.ipk"],
                                  "macos-v1.20.1": ["Nori-macOS-1.20.1-source.zip"]})

    def test_existing_release_is_not_duplicated(self) -> None:
        github = self.github(tags={"ios-v1.25.2": OTHER_COMMIT},
                             releases=[{"id": 7, "tag_name": "ios-v1.25.2", "draft": False, "assets": []}])
        self.assertEqual(self.release("ios", make_ipa(self.out), github), "skip")
        self.assertEqual(github.writes, [])
        self.assertEqual(github.tag_refs["ios-v1.25.2"], OTHER_COMMIT)
        self.assertEqual(len(github.release_list), 1)

    def test_existing_tag_creates_no_release(self) -> None:
        github = self.github(tags={"ios-v1.25.2": self.commit})
        with self.assertRaisesRegex(self.tool.ReleaseError, "ohne Release"):
            self.release("ios", make_ipa(self.out), github)
        self.assertEqual(github.writes, [])

    def test_tag_on_wrong_commit_is_an_error_and_not_moved(self) -> None:
        github = self.github(tags={"webos-v2.2.1": OTHER_COMMIT})
        with self.assertRaisesRegex(self.tool.ReleaseError, "nicht verschoben"):
            self.release("webos", make_ipk(self.out), github)
        self.assertEqual(github.writes, [])
        self.assertEqual(github.tag_refs["webos-v2.2.1"], OTHER_COMMIT)

    def test_dry_run_writes_nothing(self) -> None:
        github = self.github()
        self.assertEqual(self.release("ios", make_ipa(self.out), github, dry_run=True), "dry-run")
        self.assertEqual(github.writes, [])

    def test_commit_outside_main_is_an_error(self) -> None:
        github = self.github(main_commits=set())
        with self.assertRaisesRegex(self.tool.ReleaseError, "nicht auf main"):
            self.release("ios", make_ipa(self.out), github)
        self.assertEqual(github.writes, [])

    def test_failed_production_check_blocks_release(self) -> None:
        def failing(meta, path):
            raise self.tool.ReleaseError("Produktionsprüfung fehlgeschlagen")
        self.tool.production_check = failing
        github = self.github()
        with self.assertRaisesRegex(self.tool.ReleaseError, "Produktionsprüfung"):
            self.release("webos", make_ipk(self.out), github)
        self.assertEqual(github.writes, [])

    def test_wrong_artifact_is_an_error(self) -> None:
        github = self.github()
        with self.assertRaisesRegex(self.tool.ReleaseError, "Falsches Paket"):
            self.release("ios", make_ipa(self.out, version="1.25.2", name="Nori-iOS-1.25.1-unsigned.ipa"), github)
        with self.assertRaisesRegex(self.tool.ReleaseError, "Falsches Paket"):
            self.release("webos", make_ipa(self.out, name="tv.nori.app_2.2.1_all.zip"), github)
        other = self.out / "zwei"
        other.mkdir()
        make_ipk(other)
        (other / "tv.nori.app_2.2.1_all.log").write_text("Protokoll")
        with self.assertRaisesRegex(self.tool.ReleaseError, "genau eine Datei"):
            self.tool.find_asset(other, self.meta("webos"))
        self.assertEqual(github.writes, [])

    def test_package_differing_from_checked_package_is_an_error(self) -> None:
        github = self.github()
        checked = hashlib.sha256(make_ipk(self.out).read_bytes()).hexdigest()
        rebuilt = self.out / "neu"
        rebuilt.mkdir()
        asset = make_ipk(rebuilt, extra={"./usr/palm/applications/tv.nori.app/neu.js": b"1"})
        with self.assertRaisesRegex(self.tool.ReleaseError, "Prüfsumme"):
            self.release("webos", asset, github, sha256=checked)
        self.assertEqual(github.writes, [])

    def test_asset_version_must_match_tag(self) -> None:
        github = self.github()
        with self.assertRaisesRegex(self.tool.ReleaseError, "CFBundleShortVersionString"):
            self.release("ios", make_ipa(self.out, version="1.25.1", name="Nori-iOS-1.25.2-unsigned.ipa"), github)
        with self.assertRaisesRegex(self.tool.ReleaseError, r"Version \(control\)"):
            self.release("webos", make_ipk(self.out, control_version="2.2.0"), github)
        self.assertEqual(github.writes, [])

    def test_modified_upload_is_never_published(self) -> None:
        github = self.github()
        github.corrupt_upload = True
        with self.assertRaisesRegex(self.tool.ReleaseError, "weicht vom geprüften Paket ab"):
            self.release("ios", make_ipa(self.out), github)
        self.assertEqual(github.writes, ["draft", "upload"])
        self.assertNotIn("ios-v1.25.2", github.tag_refs)
        self.assertTrue(github.release_list[0]["draft"])

    def test_tag_race_leaves_draft_unpublished(self) -> None:
        github = self.github()
        github.tag_race = True
        with self.assertRaisesRegex(self.tool.ReleaseError, "inzwischen vorhanden"):
            self.release("ios", make_ipa(self.out), github)
        self.assertEqual(github.writes, ["draft", "upload", "tag"])
        self.assertTrue(github.release_list[0]["draft"])

    def test_publish_requires_checksum_from_package_job(self) -> None:
        code = self.tool.main(["publish", "--platform", "ios", "--dir", str(self.out), "--sha256", "", "--commit", self.commit])
        self.assertEqual(code, 1)


class VerifyTests(ReleaseTestCase):
    def assertRejected(self, key: str, path: Path, message: str) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, message):
            self.tool.verify_asset(self.meta(key), path)

    def test_valid_packages_pass(self) -> None:
        ipa = make_ipa(self.out)
        self.assertEqual(self.tool.verify_asset(self.meta("ios"), ipa, "sha256:" + hashlib.sha256(ipa.read_bytes()).hexdigest()),
                         hashlib.sha256(ipa.read_bytes()).hexdigest())
        self.tool.verify_asset(self.meta("webos"), make_ipk(self.out))
        self.tool.verify_asset(self.meta("macos"), self.source_zip())

    def test_checksum_must_match(self) -> None:
        ipa = make_ipa(self.out)
        with self.assertRaisesRegex(self.tool.ReleaseError, "Prüfsumme"):
            self.tool.verify_asset(self.meta("ios"), ipa, "0" * 64)
        with self.assertRaisesRegex(self.tool.ReleaseError, "ungültig"):
            self.tool.verify_asset(self.meta("ios"), ipa, "abc")

    def test_ipa_build_and_bundle_must_match(self) -> None:
        self.assertRejected("ios", make_ipa(self.out, build="38"), "CFBundleVersion")
        self.assertRejected("ios", make_ipa(self.out, bundle="to.nori.macos"), "Bundle-ID")

    def test_ipa_structure(self) -> None:
        self.assertRejected("ios", make_ipa(self.out, apps=("Nori.app", "Other.app")), "genau Payload/Nori.app")
        self.assertRejected("ios", make_ipa(self.out, extra={"build.txt": b"x"}), "außerhalb von Payload")
        self.assertRejected("ios", make_ipa(self.out, extra={"Payload/../evil": b"x"}), "unzulässiger Pfad")
        broken = self.out / "Nori-iOS-1.25.2-unsigned.ipa"
        broken.write_bytes(b"kein zip")
        self.assertRejected("ios", broken, "kein gültiges ZIP")

    def test_ipa_forbidden_files(self) -> None:
        for member in ("Payload/Nori.app/.env.local", "Payload/Nori.app/Config/Google.local.xcconfig",
                       "Payload/Nori.app/client_secret_1.json", "Payload/Nori.app/google-oauth.json",
                       "Payload/Nori.app/xcodebuild.log", "Payload/Nori.app/test-shots/home.png",
                       "Payload/Nori.app/embedded.mobileprovision"):
            with self.subTest(member=member):
                self.assertRejected("ios", make_ipa(self.out, extra={member: b"x"}), "unzulässige Datei")

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

    def test_ipk_versions_must_match(self) -> None:
        self.assertRejected("webos", make_ipk(self.out, control_version="2.2.0"), r"Version \(control\)")
        self.assertRejected("webos", make_ipk(self.out, appinfo_version="2.2.0"), r"appinfo\.json")
        self.assertRejected("webos", make_ipk(self.out, raw=b"kein ar"), "kein ar-Archiv")

    def test_ipk_forbidden_content(self) -> None:
        app = "./usr/palm/applications/tv.nori.app/"
        cases = {
            app + ".env.local": (b"VITE=1", "unzulässige Datei"),
            app + "client_secret_tv.json": (b"{}", "unzulässige Datei"),
            app + "assets/old.js": (OLD_TV_SECRET.encode(), "google-webos-oauth-test.json client_secret"),
            app + "assets/mac.js": (MAC_SECRET.encode(), "google-macos-oauth.json client_secret"),
            app + "assets/ios.js": (IOS_ID.encode(), "google-ios-client-id"),
            app + "assets/token.js": (REFRESH_TOKEN.encode(), "Refresh-Token"),
        }
        for member, (content, message) in cases.items():
            with self.subTest(member=member):
                self.assertRejected("webos", make_ipk(self.out, extra={member: content}), message)

    def test_source_zip_must_equal_the_commit(self) -> None:
        (self.repo / "native/Nori-macOS/Notizen.txt").write_text("nicht eingecheckt")
        self.assertRejected("macos", self.source_zip(), "gehören nicht zu Commit")
        (self.repo / "native/Nori-macOS/Notizen.txt").unlink()

        (self.repo / "native/Nori-macOS/Config/Google.local.xcconfig").write_text(f"GOOGLE_CLIENT_ID = {MAC_ID}\n")
        self.assertRejected("macos", self.source_zip(), "unzulässige Datei")
        (self.repo / "native/Nori-macOS/Config/Google.local.xcconfig").unlink()

        (self.repo / "README.md").write_text("# Nori, lokal geändert\n")
        self.assertRejected("macos", self.source_zip(), "README.md weicht vom Stand")
        git(self.repo, "checkout", "--", "README.md")

        self.assertRejected("macos", self.source_zip(exclude=("README.md",)), "fehlen")

    def test_source_zip_from_older_commit_is_rejected(self) -> None:
        older = self.source_zip()
        self.commit_file("native/Nori-macOS/Nori/NoriApp.swift", "@main struct NoriApp { let neu = 1 }\n")
        self.assertRejected("macos", older, "NoriApp.swift weicht vom Stand")

    def test_find_asset_requires_exactly_one_file(self) -> None:
        empty = self.out / "leer"
        empty.mkdir()
        with self.assertRaisesRegex(self.tool.ReleaseError, "enthält 0"):
            self.tool.find_asset(empty, self.meta("ios"))


class NotesTests(ReleaseTestCase):
    def notes(self, key: str) -> str:
        return self.tool.build_notes(self.meta(key), "owner/nori")

    def test_ios_notes(self) -> None:
        notes = self.notes("ios")
        for expected in ("**Plattform:** iOS/iPadOS", "**Version:** 1.25.2", "**Build:** 39",
                         f"[`{self.commit[:7]}`](https://github.com/owner/nori/commit/{self.commit})",
                         "> Unsigned IPA – muss vor der Installation mit einer gültigen Signatur signiert werden.",
                         "### Behoben — beide Apple-Apps", "### Behoben — iOS/iPadOS",
                         "- **Nach dem Countdown startete die nächste Folge nicht.** Die neue Folge startet",
                         "  - Unterpunkt ohne Einzelheiten.", "Abschließende Apple-Prüfung, z. B. Player auf iPad und Mac."):
            self.assertIn(expected, notes)
        for unexpected in ("Behoben — macOS", "Geprüft, ohne Änderung", "Bild-Cache", "configure-google-oauth",
                           "Refresh-Token", "OAuth", "webOS 2.2.1", "Paketierungsfehler"):
            self.assertNotIn(unexpected, notes)

    def test_macos_notes(self) -> None:
        notes = self.notes("macos")
        self.assertIn("### Behoben — macOS", notes)
        self.assertIn("### Behoben — beide Apple-Apps", notes)
        self.assertNotIn("iOS/iPadOS", notes)
        self.assertIn("**Build:** 30", notes)
        self.assertIn("Paket: `Nori-macOS-1.20.1-source.zip`", notes)

    def test_webos_notes_leave_out_internal_credential_details(self) -> None:
        notes = self.notes("webos")
        self.assertIn("> Installationspaket für LG webOS.", notes)
        self.assertNotIn("**Build:**", notes)
        self.assertIn("Nur ein Paketierungsfehler. iOS und macOS unverändert.", notes)
        self.assertIn("- **Das installierbare Paket hatte keinen Google-Zugang.**\n- Die Liste lädt schneller.", notes)
        for unexpected in ("VITE_", ".env", "OAuth", "Zugangsdaten", "secrets", "Runner", "22 neue Tests"):
            self.assertNotIn(unexpected, notes)

    def test_missing_changelog_section_is_an_error(self) -> None:
        self.commit_file("CHANGELOG.md", CHANGELOG.replace("[webOS 2.2.1]", "[webOS 2.2.0]"))
        with self.assertRaisesRegex(self.tool.ReleaseError, r"keinen Abschnitt \[webOS 2\.2\.1\]"):
            self.notes("webos")

    def test_public_text_check_rejects_credentials(self) -> None:
        for text in (f"Wert {TV_ID}", f"Wert {SECRET_PREFIX}inventedSecretValue123", f"Wert {ACCESS_TOKEN}",
                     "Der OAuth-Client wurde getauscht.", "kopiert aus der .env.local"):
            with self.subTest(text=text[:20]):
                with self.assertRaises(self.tool.ReleaseError):
                    self.tool.check_public_text(text)
        self.tool.check_public_text("Die Liste lädt schneller.")


class FromRunTests(ReleaseTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.platform = self.tool.PLATFORMS["ios"]
        self.github_fake = self.github()
        artifact_dir = self.temp / "artifact"
        artifact_dir.mkdir()
        self.github_fake.artifact_files[5] = make_ipa(artifact_dir)
        self.run_data = {"id": 42, "path": self.platform.workflow, "head_branch": "main", "head_sha": self.commit,
                         "event": "push", "status": "completed", "conclusion": "success"}
        self.github_fake.runs["42"] = self.run_data
        self.github_fake.job_lists["42"] = [{"name": "package", "conclusion": "success", "steps": [
            {"name": name, "conclusion": "success"} for name in self.platform.required_steps]}]
        self.github_fake.artifact_lists["42"] = [{"id": 5, "name": "Nori-iOS-1.25.2-unsigned", "expired": False}]
        self.github_fake.latest[self.platform.workflow] = self.run_data

    def from_run(self, dry_run: bool = False):
        return self.tool.release_from_run("ios", "42", self.github_fake, "owner/nori", dry_run)

    def assertRefused(self, message: str) -> None:
        with self.assertRaisesRegex(self.tool.ReleaseError, message):
            self.from_run()
        self.assertEqual(self.github_fake.writes, [])
        self.assertEqual(self.github_fake.downloads, [])

    def test_successful_latest_run_is_released(self) -> None:
        self.assertEqual(self.from_run(), "created")
        self.assertEqual(self.github_fake.tag_refs["ios-v1.25.2"], self.commit)
        self.assertEqual(self.production_calls, ["Nori-iOS-1.25.2-unsigned.ipa"])

    def test_failed_or_cancelled_packaging_creates_no_release(self) -> None:
        for conclusion in ("failure", "cancelled", "timed_out", None):
            with self.subTest(conclusion=conclusion):
                self.run_data["conclusion"] = conclusion
                self.assertRefused("nicht erfolgreich")

    def test_failed_verification_step_creates_no_release(self) -> None:
        self.github_fake.job_lists["42"][0]["steps"][1]["conclusion"] = "skipped"
        self.assertRefused("Google OAuth in der fertigen IPA prüfen")

    def test_run_must_be_main_push_of_the_packaging_workflow(self) -> None:
        for field, value, message in (("head_branch", "claude/test", "nicht auf main"),
                                      ("event", "pull_request", "pull_request"),
                                      ("path", ".github/workflows/build-ios.yml", "erwartet")):
            with self.subTest(field=field):
                original = self.run_data[field]
                self.run_data[field] = value
                self.assertRefused(message)
                self.run_data[field] = original

    def test_only_the_latest_successful_run(self) -> None:
        self.github_fake.latest[self.platform.workflow] = {"id": 43}
        self.assertRefused("jüngste")

    def test_run_for_another_version_is_refused(self) -> None:
        self.commit_file("native/Nori-iOS/Nori.xcodeproj/project.pbxproj", pbxproj("1.25.3", "40", "to.nori.ios"))
        self.assertRefused("anderen Stand")

    def test_expired_artifact_is_refused(self) -> None:
        self.github_fake.artifact_lists["42"][0]["expired"] = True
        with self.assertRaisesRegex(self.tool.ReleaseError, "abgelaufen"):
            self.from_run()
        self.assertEqual(self.github_fake.writes, [])


class _Handler(http.server.BaseHTTPRequestHandler):
    def _handle(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        path = self.path.split("?")[0]
        self.server.seen.append((self.command, path, self.headers.get("Authorization"), body))
        status, headers, payload = self.server.routes.get((self.command, path), (404, {}, b'{"message": "Not Found"}'))
        self.send_response(status)
        for name, value in headers.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_PATCH = _handle

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

    def route(self, method: str, path: str, status: int = 200, payload: object = None, headers=None, raw: bytes | None = None):
        body = raw if raw is not None else json.dumps(payload if payload is not None else {}).encode()
        self.server.routes[(method, path)] = (status, headers or {}, body)

    def test_missing_tag_and_annotated_tag(self) -> None:
        self.assertIsNone(self.github.tag_commit("ios-v1.25.2"))
        self.route("GET", "/repos/owner/nori/git/ref/tags/ios-v1.25.2",
                   payload={"ref": "refs/tags/ios-v1.25.2", "object": {"type": "tag", "sha": "t" * 40}})
        self.route("GET", f"/repos/owner/nori/git/tags/{'t' * 40}", payload={"object": {"type": "commit", "sha": "c" * 40}})
        self.assertEqual(self.github.tag_commit("ios-v1.25.2"), "c" * 40)

    def test_existing_tag_reference_fails_with_422(self) -> None:
        self.route("POST", "/repos/owner/nori/git/tags", 201, {"sha": "t" * 40})
        self.route("POST", "/repos/owner/nori/git/refs", 422, {"message": "Reference already exists"})
        with self.assertRaises(self.tool.GitHubError) as caught:
            self.github.create_tag("ios-v1.25.2", "c" * 40, "Nori iOS 1.25.2")
        self.assertEqual(caught.exception.status, 422)
        self.assertNotIn(self.TOKEN, str(caught.exception))
        self.assertEqual([method for method, *_ in self.server.seen], ["POST", "POST"])

    def test_token_is_not_forwarded_on_redirects(self) -> None:
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, "w") as handle:
            handle.writestr("tv.nori.app_2.2.1_all.ipk", b"!<arch>\n")
        self.route("GET", "/repos/owner/nori/actions/artifacts/5/zip", 302, headers={"Location": f"{self.base}/blob"})
        self.route("GET", "/blob", raw=archive.getvalue())
        with tempfile.TemporaryDirectory() as temp:
            self.github.download_artifact({"id": 5, "name": "Nori-webOS"}, Path(temp))
            self.assertTrue((Path(temp) / "tv.nori.app_2.2.1_all.ipk").is_file())
        authorization = {path: header for _, path, header, _ in self.server.seen}
        self.assertEqual(authorization["/repos/owner/nori/actions/artifacts/5/zip"], f"Bearer {self.TOKEN}")
        self.assertIsNone(authorization["/blob"])

    def test_errors_do_not_contain_the_token(self) -> None:
        self.route("GET", "/repos/owner/nori/releases/tags/ios-v1.25.2", 500, {"message": "boom"})
        with self.assertRaises(self.tool.GitHubError) as caught:
            self.github.release_by_tag("ios-v1.25.2")
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


class WorkflowTests(unittest.TestCase):
    CASES = (
        ("package-ios-ipa.yml", "package", "ios",
         ("Google OAuth im gebauten Programm prüfen", "In eine IPA packen", "Google OAuth in der fertigen IPA prüfen"),
         "IPA für den Release prüfen", "IPA hochladen"),
        ("build-webos.yml", "build", "webos",
         ("Fernbedienung durchspielen", "Google-TV-OAuth bereitstellen", "webOS-App produktiv bauen",
          "Paket schnüren", "Paket prüfen"),
         "Paket für den Release prüfen", "Paket als Artefakt ablegen"),
        ("package-macos-source.yml", "package", "macos",
         ("Create macOS source package",), "Quellpaket prüfen", "Upload package"),
    )

    def test_release_is_only_called_never_triggered_by_tags(self) -> None:
        on = triggers(load_workflow("release.yml"))
        self.assertIn("workflow_call", on)
        self.assertNotIn("push", on)
        self.assertNotIn("pull_request", on)

    def test_release_runs_only_after_the_successful_package_job_on_main(self) -> None:
        for name, job, platform, before, verify, upload in self.CASES:
            with self.subTest(workflow=name):
                workflow = load_workflow(name)
                jobs = workflow["jobs"]
                self.assertEqual(set(jobs), {job, "release"})
                release = jobs["release"]
                self.assertEqual(release["uses"], "./.github/workflows/release.yml")
                needs = release["needs"] if isinstance(release["needs"], list) else [release["needs"]]
                self.assertEqual(needs, [job])
                condition = release.get("if", "")
                self.assertIn("github.ref == 'refs/heads/main'", condition)
                for bypass in ("always()", "failure()", "cancelled()"):
                    self.assertNotIn(bypass, condition)
                self.assertEqual(release["with"]["platform"], platform)
                self.assertIn(f"needs.{job}.outputs.sha256", release["with"]["sha256"])
                self.assertEqual(release["permissions"]["contents"], "write")

                package = jobs[job]
                self.assertNotIn("continue-on-error", package)
                self.assertIn("steps.release-check.outputs.sha256", package["outputs"]["sha256"])
                steps = package["steps"]
                names = [step.get("name") for step in steps]
                for step in steps:
                    self.assertFalse(step.get("continue-on-error"), step.get("name"))
                for earlier in before:
                    self.assertLess(names.index(earlier), names.index(verify), earlier)
                self.assertLess(names.index(verify), names.index(upload))
                check = steps[names.index(verify)]
                self.assertEqual(check.get("id"), "release-check")
                self.assertIn("tools/nori-release.py verify", check["run"])
                self.assertIn("--github-output", check["run"])

    def test_webos_releases_the_production_package(self) -> None:
        steps = load_workflow("build-webos.yml")["jobs"]["build"]["steps"]
        by_name = {step.get("name"): step for step in steps}
        self.assertIn("--production", by_name["Paket prüfen"]["run"])
        self.assertIn("--reference-dist", by_name["Paket prüfen"]["run"])
        self.assertEqual(by_name["Paket als Artefakt ablegen"]["with"]["path"], "apps/webos/*.ipk")

    def test_main_runs_are_not_cancelled_mid_release(self) -> None:
        for name, *_ in self.CASES:
            with self.subTest(workflow=name):
                cancel = str(load_workflow(name)["concurrency"]["cancel-in-progress"])
                self.assertIn("refs/heads/main", cancel)

    def test_release_job_publishes_only_through_the_tool(self) -> None:
        workflow = load_workflow("release.yml")
        job = workflow["jobs"]["release"]
        self.assertFalse(job["concurrency"]["cancel-in-progress"])
        steps = job["steps"]
        names = [step.get("name") for step in steps]
        runs = "\n".join(step.get("run", "") for step in steps)
        for forbidden in ("gh release", "curl", "git push", "git tag", "--force", "upload-artifact"):
            self.assertNotIn(forbidden, runs)
        self.assertFalse(any("upload-artifact" in str(step.get("uses", "")) for step in steps))
        checkout = next(step for step in steps if str(step.get("uses", "")).startswith("actions/checkout"))
        self.assertFalse(checkout["with"]["persist-credentials"])
        publish = next(step for step in steps if "nori-release.py publish" in step.get("run", ""))
        self.assertIn('--commit "$GITHUB_SHA"', publish["run"])
        self.assertIn("--sha256", publish["run"])
        self.assertLess(names.index("Release-Werkzeug prüfen"), steps.index(publish))
        download = next(step for step in steps if str(step.get("uses", "")).startswith("actions/download-artifact"))
        self.assertEqual(download["with"]["name"], "${{ inputs.artifact }}")


class CurrentRepositoryTests(unittest.TestCase):
    """Die aktuellen Versionen im echten Repository haben öffentliche Notes."""

    def setUp(self) -> None:
        self.tool = load_tool()
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.tool.SECRETS_DIR = Path(self.temp.name) / "keine-secrets"

    def test_current_versions_have_public_release_notes(self) -> None:
        for key in self.tool.PLATFORMS:
            with self.subTest(platform=key):
                meta = self.tool.read_meta(key, "HEAD")
                notes = self.tool.build_notes(meta, "owner/nori")
                self.assertIn(f"**Version:** {meta.version}", notes)
                self.assertIn(meta.platform.hint, notes)
                self.assertIsNone(self.tool.SENSITIVE.search(notes))


if __name__ == "__main__":
    unittest.main()
