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

import json
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


    # MARK: - webOS: produktive TV-Konfiguration

    def write_webos_json(self, document: object, name: str = "google-webos-oauth.json") -> None:
        path = self.home / ".config/nori/secrets" / name
        path.write_text(document if isinstance(document, str) else json.dumps(document))

    def assert_webos_rejected(self, reason: str) -> None:
        result = self.run_tool("--webos")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(reason, result.stdout)
        self.assertNotIn("Google TV OAuth: configured", result.stdout)
        self.assertFalse((self.root / "apps/webos/.env.local").exists())

    def test_webos_configuration_from_secrets_json(self) -> None:
        self.write_webos_json({"installed": {"client_id": FAKE_ID, "client_secret": FAKE_SECRET}})
        result = self.run_tool("--webos")
        self.assertEqual(result.returncode, 0, result.stdout)
        for line in ("Google TV OAuth: configured", "Google TV Client ID: valid", "Google TV Client Secret: included"):
            self.assertIn(line, result.stdout)
        self.assertNotIn(FAKE_ID, result.stdout)
        self.assertNotIn(FAKE_SECRET, result.stdout)
        env = self.root / "apps/webos/.env.local"
        written = env.read_text()
        self.assertIn(f"VITE_NORI_GOOGLE_TV_CLIENT_ID={FAKE_ID}", written)
        self.assertIn(f"VITE_NORI_GOOGLE_TV_CLIENT_SECRET={FAKE_SECRET}", written)
        self.assertEqual(env.stat().st_mode & 0o777, 0o600)

    def test_webos_missing_json_is_a_hard_error(self) -> None:
        self.assert_webos_rejected("google-webos-oauth.json fehlt")

    def test_webos_invalid_json_is_rejected(self) -> None:
        self.write_webos_json("{ kaputt")
        self.assert_webos_rejected("kein gültiges JSON")

    def test_webos_missing_client_id_is_rejected(self) -> None:
        self.write_webos_json({"installed": {"client_secret": FAKE_SECRET}})
        self.assert_webos_rejected("client_id fehlt")

    def test_webos_missing_client_secret_is_rejected(self) -> None:
        self.write_webos_json({"installed": {"client_id": FAKE_ID}})
        self.assert_webos_rejected("client_secret fehlt")

    def test_webos_empty_values_are_rejected(self) -> None:
        self.write_webos_json({"installed": {"client_id": "  ", "client_secret": FAKE_SECRET}})
        self.assert_webos_rejected("client_id in google-webos-oauth.json ist leer")
        self.write_webos_json({"installed": {"client_id": FAKE_ID, "client_secret": "   "}})
        self.assert_webos_rejected("client_secret in google-webos-oauth.json ist leer")

    def test_webos_placeholder_values_are_rejected(self) -> None:
        self.write_webos_json({"installed": {"client_id": "000000000000-beispiel" + SUFFIX, "client_secret": FAKE_SECRET}})
        self.assert_webos_rejected("Platzhalter")
        self.write_webos_json({"installed": {"client_id": FAKE_ID, "client_secret": "<aus-der-OAuth-JSON>"}})
        self.assert_webos_rejected("Platzhalter")

    def test_webos_wrong_client_id_form_is_rejected(self) -> None:
        self.write_webos_json({"installed": {"client_id": "123456789012-abc.example.org", "client_secret": FAKE_SECRET}})
        self.assert_webos_rejected("google-webos-oauth.json")

    def test_webos_desktop_client_is_rejected(self) -> None:
        self.write_webos_json({"installed": {"client_id": FAKE_ID, "client_secret": FAKE_SECRET, "redirect_uris": ["http://localhost"]}})
        self.assert_webos_rejected("kein TV-Client")

    def test_webos_web_client_is_rejected(self) -> None:
        self.write_webos_json({"web": {"client_id": FAKE_ID, "client_secret": FAKE_SECRET}})
        self.assert_webos_rejected("erwartet `installed`")

    def test_macos_desktop_client_is_still_accepted(self) -> None:
        path = self.home / ".config/nori/secrets/google-macos-oauth.json"
        path.write_text(json.dumps({"installed": {"client_id": FAKE_ID, "client_secret": FAKE_SECRET, "redirect_uris": ["http://localhost"]}}))
        result = self.run_tool("--macos")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(f"GOOGLE_CLIENT_SECRET = {FAKE_SECRET}", (self.root / "native/Nori-macOS/Config/Google.local.xcconfig").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
