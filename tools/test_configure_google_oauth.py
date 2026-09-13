#!/usr/bin/env python3
"""Regressionstest für das iOS-Paket: ohne Google-Client-ID darf keine IPA durchgehen.

Anlass: Nori 1.25.0 (37) wurde als IPA mit leerer `GoogleClientID` gebaut und
hochgeladen — die App meldete „Diese Nori-Fassung wurde ohne Google-Abgleich
gebaut". Der Build lief grün, weil eine fehlende Konfiguration für
Entwicklungs-Builds ausdrücklich erlaubt ist und niemand das fertige Paket
geprüft hat.

Geprüft wird `tools/configure-google-oauth.py` als Programm, in einer Kopie in
einem leeren Verzeichnis und mit eigenem `HOME`: nichts aus diesem Rechner —
keine lokale Konfiguration, keine OAuth-Datei — fließt ein, und nichts wird
überschrieben. Die Client-IDs hier sind erfunden und werden zur Laufzeit
zusammengesetzt, damit keine Prüfung des Repositorys sie für echte hält.

    python3 tools/test_configure_google_oauth.py
"""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "configure-google-oauth.py"
SUFFIX = ".apps.googleusercontent.com"
FAKE_ID = "123456789012-" + "abcdefghijklmnopqrstuvwxyz012345" + SUFFIX
OTHER_ID = "123456789012-" + "zyxwvutsrqponmlkjihgfedcba543210" + SUFFIX
FAKE_SECRET = "GOCSPX" + "-" + "t" * 24


class PackagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="nori-oauth-test-"))
        self.root = self.tmp / "repo"
        (self.root / "tools").mkdir(parents=True)
        shutil.copy(TOOL, self.root / "tools" / TOOL.name)
        self.home = self.tmp / "home"
        (self.home / ".config/nori/secrets").mkdir(parents=True)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    # MARK: - Hilfen

    def run_tool(self, *args: str) -> subprocess.CompletedProcess:
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(self.home), "CI": "true"}
        return subprocess.run(
            [sys.executable, str(self.root / "tools" / TOOL.name), *args],
            capture_output=True, text=True, env=env, cwd=self.root,
        )

    def make_app(self, info: dict, extra: dict[str, bytes] | None = None) -> Path:
        app = self.tmp / f"build-{len(list(self.tmp.iterdir()))}" / "Nori.app"
        app.mkdir(parents=True)
        base = {"CFBundleIdentifier": "to.nori.ios", "CFBundleShortVersionString": "9.9.9"}
        (app / "Info.plist").write_bytes(plistlib.dumps({**base, **info}, fmt=plistlib.FMT_BINARY))
        (app / "Nori").write_bytes(b"\xcf\xfa\xed\xfe binary")
        for name, data in (extra or {}).items():
            (app / name).write_bytes(data)
        return app

    def make_ipa(self, app: Path) -> Path:
        ipa = app.parent / "Nori-test.ipa"
        with zipfile.ZipFile(ipa, "w") as archive:
            for file in app.rglob("*"):
                archive.write(file, Path("Payload") / file.relative_to(app.parent))
        return ipa

    def assert_rejected(self, result: subprocess.CompletedProcess, reason: str) -> None:
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(reason, result.stdout)
        self.assertNotIn("Google OAuth: configured", result.stdout)

    # MARK: - Das fertige Programm

    def test_valid_bundle_passes_without_printing_the_id(self) -> None:
        result = self.run_tool("--verify-ios-app", str(self.make_app({"GoogleClientID": FAKE_ID})))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Google OAuth: configured", result.stdout)
        self.assertIn("Google Client-Secret: not included", result.stdout)
        self.assertNotIn(FAKE_ID, result.stdout)

    def test_missing_client_id_is_rejected(self) -> None:
        self.assert_rejected(self.run_tool("--verify-ios-app", str(self.make_app({}))), "GoogleClientID fehlt")

    def test_empty_client_id_is_rejected(self) -> None:
        # Genau der Fehler aus 1.25.0 (37): der Schlüssel steht da, leer.
        result = self.run_tool("--verify-ios-app", str(self.make_app({"GoogleClientID": ""})))
        self.assert_rejected(result, "GoogleClientID ist leer")

    def test_unresolved_placeholder_is_rejected(self) -> None:
        result = self.run_tool("--verify-ios-app", str(self.make_app({"GoogleClientID": "$(GOOGLE_CLIENT_ID)"})))
        self.assert_rejected(result, "unaufgelöster Platzhalter")

    def test_wrong_suffix_is_rejected(self) -> None:
        result = self.run_tool("--verify-ios-app", str(self.make_app({"GoogleClientID": "123456789012-abc.example.com"})))
        self.assert_rejected(result, "endet nicht auf")

    def test_client_secret_key_is_rejected(self) -> None:
        app = self.make_app({"GoogleClientID": FAKE_ID, "GoogleClientSecret": FAKE_SECRET})
        result = self.run_tool("--verify-ios-app", str(app))
        self.assertEqual(result.returncode, 1)
        self.assertIn("GoogleClientSecret", result.stdout)
        self.assertNotIn(FAKE_SECRET, result.stdout)

    def test_secret_pattern_anywhere_in_bundle_is_rejected(self) -> None:
        app = self.make_app({"GoogleClientID": FAKE_ID}, {"leak.json": FAKE_SECRET.encode()})
        result = self.run_tool("--verify-ios-app", str(app))
        self.assertEqual(result.returncode, 1)
        self.assertIn("Format eines Google-Client-Secrets", result.stdout)
        self.assertNotIn(FAKE_SECRET, result.stdout)

    def test_foreign_client_id_in_bundle_is_rejected(self) -> None:
        app = self.make_app({"GoogleClientID": FAKE_ID}, {"other.txt": OTHER_ID.encode()})
        result = self.run_tool("--verify-ios-app", str(app))
        self.assertEqual(result.returncode, 1)
        self.assertIn("fremde Client-ID", result.stdout)
        self.assertNotIn(OTHER_ID, result.stdout)

    def test_client_id_must_match_the_machine_configuration(self) -> None:
        (self.home / ".config/nori/secrets/google-ios-client-id").write_text(OTHER_ID + "\n")
        result = self.run_tool("--verify-ios-app", str(self.make_app({"GoogleClientID": FAKE_ID})))
        self.assert_rejected(result, "nicht die iOS-Client-ID dieses Rechners")

    # MARK: - Die IPA selbst

    def test_valid_ipa_passes(self) -> None:
        ipa = self.make_ipa(self.make_app({"GoogleClientID": FAKE_ID}))
        result = self.run_tool("--verify-ios-ipa", str(ipa))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("Google OAuth: configured", result.stdout)

    def test_ipa_with_empty_client_id_is_rejected(self) -> None:
        ipa = self.make_ipa(self.make_app({"GoogleClientID": ""}))
        self.assert_rejected(self.run_tool("--verify-ios-ipa", str(ipa)), "GoogleClientID ist leer")

    def test_broken_ipa_is_rejected(self) -> None:
        broken = self.tmp / "broken.ipa"
        broken.write_bytes(b"kein zip")
        self.assert_rejected(self.run_tool("--verify-ios-ipa", str(broken)), "kein gültiges ZIP-Archiv")

    # MARK: - Konfiguration schreiben

    def test_ios_configuration_without_source_is_a_hard_error(self) -> None:
        result = self.run_tool("--ios")
        self.assertEqual(result.returncode, 1)
        self.assertIn("google-ios-client-id fehlt", result.stdout)
        self.assertFalse((self.root / "native/Nori-iOS/Config/Google.local.xcconfig").exists())

    def test_ios_configuration_from_secrets_file(self) -> None:
        (self.home / ".config/nori/secrets/google-ios-client-id").write_text(FAKE_ID + "\n")
        result = self.run_tool("--ios")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn(FAKE_ID, result.stdout)
        written = (self.root / "native/Nori-iOS/Config/Google.local.xcconfig").read_text()
        self.assertIn(f"GOOGLE_CLIENT_ID = {FAKE_ID}", written)
        self.assertNotIn("SECRET", written)
        mode = (self.root / "native/Nori-iOS/Config/Google.local.xcconfig").stat().st_mode & 0o777
        self.assertEqual(mode, 0o600)

    def test_invalid_secrets_file_is_rejected(self) -> None:
        (self.home / ".config/nori/secrets/google-ios-client-id").write_text("keine-id\n")
        result = self.run_tool("--ios")
        self.assertEqual(result.returncode, 1)
        self.assertIn("enthält keine Google-Client-ID", result.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
