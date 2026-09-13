#!/usr/bin/env python3
"""Regressionstest: das produktive webOS-Paket trägt genau die TV-Zugangsdaten.

Anlass: `Build webOS` baute das installierbare `.ipk` ohne Google-TV-Client;
auf dem Fernseher stand „Google-Zugang im Build: nicht verfügbar", und der Lauf
war trotzdem grün. `tools/check-webos-package.py --production` prüft seitdem das
fertige Paket selbst — diese Tests halten fest, was es erkennt.

Alles hier ist erfunden: Pakete, Secrets-Ordner, Client-IDs und Secrets werden
zur Laufzeit zusammengesetzt, damit keine Prüfung des Repositorys sie für echte
hält. Kein Test liest `~/.config/nori/secrets` oder das echte Repository.

    python3 tools/test_check_webos_package.py
"""

from __future__ import annotations

import gzip
import importlib.util
import io
import json
import shutil
import tarfile
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "check-webos-package.py"
SUFFIX = ".apps.googleusercontent.com"
PREFIX = "GOCSPX" + "-"

TV_ID = "111111111111-" + "tvclient" * 4 + SUFFIX
TV_SECRET = PREFIX + "tvSecretFake" + "T" * 16
OTHER_TV_ID = "444444444444-" + "oldtvcli" * 4 + SUFFIX
OTHER_TV_SECRET = PREFIX + "oldTvSecret" + "Q" * 16
IOS_ID = "222222222222-" + "iosclien" * 4 + SUFFIX
MAC_ID = "333333333333-" + "macclien" * 4 + SUFFIX
MAC_SECRET = PREFIX + "macSecretFake" + "M" * 16
UNKNOWN_ID = "555555555555-" + "unknownc" * 4 + SUFFIX
UNKNOWN_SECRET = PREFIX + "unknownSecret" + "U" * 16

APP_ROOT = "usr/palm/applications/tv.nori.app"


def load_tool():
    spec = importlib.util.spec_from_file_location("check_webos_package", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bundle(client_id: str = TV_ID, secret: str = TV_SECRET) -> bytes:
    """Das Stück Bündel, in dem Vite die Zugangsdaten einsetzt."""
    return ("!function(){var e={clientId:" + json.dumps(client_id) + ",clientSecret:" + json.dumps(secret)
            + "};window.nori=e}();").encode()


class CheckWebosPackageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tool = load_tool()
        self.tmp = Path(tempfile.mkdtemp(prefix="nori-webos-check-"))
        # Keine lokalen Apple-Konfigurationen aus dem echten Checkout mitlesen.
        self.tool.ROOT = self.tmp / "repo"
        self.secrets = self.tmp / "secrets"
        self.secrets.mkdir()
        self.write_json("google-webos-oauth.json", {"installed": {"client_id": TV_ID, "client_secret": TV_SECRET}})
        self.write_json("google-webos-oauth-test.json", {"installed": {"client_id": OTHER_TV_ID, "client_secret": OTHER_TV_SECRET}})
        self.write_json("google-macos-oauth.json", {"installed": {
            "client_id": MAC_ID, "client_secret": MAC_SECRET, "redirect_uris": ["http://localhost"],
        }})
        (self.secrets / "google-ios-client-id").write_text(IOS_ID + "\n")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    # MARK: - Hilfen

    def write_json(self, name: str, document: dict) -> Path:
        path = self.secrets / name
        path.write_text(json.dumps(document))
        return path

    def make_ipk(self, files: dict[str, bytes]) -> Path:
        def tar_gz(entries: dict[str, bytes]) -> bytes:
            buffer = io.BytesIO()
            with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
                for name, data in entries.items():
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))
            return buffer.getvalue()

        def ar_entry(name: str, data: bytes) -> bytes:
            header = name.ljust(16).encode() + b"0".ljust(12) + b"0".ljust(6) + b"0".ljust(6)
            header += b"100644".ljust(8) + str(len(data)).encode().ljust(10) + b"`\n"
            return header + data + (b"\n" if len(data) % 2 else b"")

        data = {f"{APP_ROOT}/{name}": content for name, content in files.items()}
        data["usr/palm/packages/tv.nori.app/packageinfo.json"] = b'{"id": "tv.nori.app", "version": "9.9.9"}'
        raw = b"!<arch>\n" + ar_entry("debian-binary", b"2.0\n")
        raw += ar_entry("control.tar.gz", tar_gz({"control": b"Package: tv.nori.app\n"}))
        raw += ar_entry("data.tar.gz", tar_gz(data))
        path = self.tmp / f"tv.nori.app_{len(list(self.tmp.glob('*.ipk')))}_all.ipk"
        path.write_bytes(raw)
        return path

    def package(self, script: bytes | None = None, extra: dict[str, bytes] | None = None) -> Path:
        files = {
            "index.html": b'<script defer src="./assets/index-AbCd1234.js"></script>',
            "assets/index-AbCd1234.js": bundle() if script is None else script,
            "appinfo.json": b'{"id": "tv.nori.app", "version": "9.9.9"}',
        }
        files.update(extra or {})
        return self.make_ipk(files)

    def check(self, package: Path, production: bool = True, reference: Path | None = None, webos_json: Path | None = None):
        errors, passed = self.tool.check_package_credentials(
            package, production, self.secrets, webos_json or self.secrets / "google-webos-oauth.json", reference,
        )
        for message in errors + passed:
            for value in (TV_ID, TV_SECRET, OTHER_TV_ID, OTHER_TV_SECRET, IOS_ID, MAC_ID, MAC_SECRET, UNKNOWN_ID, UNKNOWN_SECRET):
                self.assertNotIn(value, message, "Ein Wert steht in der Ausgabe")
        return errors, passed

    def assert_failed(self, result, reason: str) -> None:
        errors, passed = result
        self.assertTrue(any(reason in error for error in errors), f"erwartet „{reason}“, bekommen: {errors}")
        self.assertNotIn("Google TV OAuth: configured", passed)

    # MARK: - Produktives Paket

    def test_01_correct_production_package_passes(self) -> None:
        errors, passed = self.check(self.package())
        self.assertEqual(errors, [])
        for line in ("Google TV OAuth: configured", "Google TV Client ID: valid",
                     "Google TV Client Secret: included", "No foreign OAuth credentials found"):
            self.assertIn(line, passed)

    def test_02_missing_client_id_fails(self) -> None:
        script = b'!function(){var e={clientSecret:' + json.dumps(TV_SECRET).encode() + b'}}();'
        self.assert_failed(self.check(self.package(script)), "Client-ID fehlt")

    def test_03_empty_client_id_fails(self) -> None:
        self.assert_failed(self.check(self.package(bundle(client_id=""))), "Client-ID fehlt")

    def test_04_wrong_client_id_fails(self) -> None:
        result = self.check(self.package(bundle(client_id=UNKNOWN_ID)))
        self.assert_failed(result, "Client-ID fehlt")
        self.assert_failed(result, "weitere Client-ID")

    def test_05_missing_client_secret_fails(self) -> None:
        self.assert_failed(self.check(self.package(bundle(secret=""))), "Client-Secret fehlt")

    def test_06_wrong_client_secret_fails(self) -> None:
        result = self.check(self.package(bundle(secret=UNKNOWN_SECRET)))
        self.assert_failed(result, "Client-Secret fehlt")
        self.assert_failed(result, "weitere(s) Client-Secret")

    def test_07_ios_client_id_in_package_fails(self) -> None:
        result = self.check(self.package(extra={"assets/extra.js": IOS_ID.encode()}))
        self.assert_failed(result, "fremde Zugangsdaten im Paket — iOS-Client-ID")

    def test_08_macos_client_id_in_package_fails(self) -> None:
        result = self.check(self.package(extra={"assets/extra.js": MAC_ID.encode()}))
        self.assert_failed(result, "google-macos-oauth.json (installed.client_id)")

    def test_09_macos_secret_in_package_fails(self) -> None:
        result = self.check(self.package(extra={"assets/extra.js": MAC_SECRET.encode()}))
        self.assert_failed(result, "google-macos-oauth.json (installed.client_secret)")

    def test_10_oauth_json_in_package_fails(self) -> None:
        document = json.dumps({"installed": {"client_id": TV_ID, "client_secret": TV_SECRET}}).encode()
        result = self.check(self.package(extra={"google-webos-oauth.json": document}))
        self.assert_failed(result, "Datei mit Zugangsdaten im Paket")

    def test_11_env_local_in_package_fails(self) -> None:
        env = f"VITE_NORI_GOOGLE_TV_CLIENT_ID={TV_ID}\n".encode()
        self.assert_failed(self.check(self.package(extra={".env.local": env})), "Datei mit Zugangsdaten im Paket")

    def test_12_token_patterns_in_package_fail(self) -> None:
        access = ("ya" + "29." + "a" * 40).encode()
        refresh = ('{"refresh_token":"' + "1/" + "/0" + "r" * 40 + '"}').encode()
        device = b'{"device_code":"AH-1NgFakeDeviceCode1234567890"}'
        cookie = b"Set-Cookie: SID=abc"
        for payload, reason in ((access, "Access-Token"), (refresh, "Refresh-Token"),
                                (device, "Gerätecode"), (cookie, "Cookie")):
            with self.subTest(reason=reason):
                self.assert_failed(self.check(self.package(extra={"assets/leak.js": payload})), reason)

    def test_13_dev_package_without_oauth_is_accepted(self) -> None:
        errors, passed = self.check(self.package(bundle(client_id="", secret="")), production=False)
        self.assertEqual(errors, [])
        self.assertEqual(passed, [])

    # MARK: - Weitere Fälle

    def test_old_test_tv_credentials_fail(self) -> None:
        result = self.check(self.package(extra={"assets/extra.js": OTHER_TV_ID.encode() + OTHER_TV_SECRET.encode()}))
        self.assert_failed(result, "google-webos-oauth-test.json (installed.client_id)")
        self.assert_failed(result, "google-webos-oauth-test.json (installed.client_secret)")

    def test_dev_mode_still_rejects_forbidden_files_and_tokens(self) -> None:
        result = self.check(self.package(extra={".env.local": b"X=1"}), production=False)
        self.assert_failed(result, "Datei mit Zugangsdaten im Paket")

    def test_missing_production_json_fails(self) -> None:
        result = self.check(self.package(), webos_json=self.secrets / "fehlt.json")
        self.assert_failed(result, "fehlt")

    def test_desktop_client_json_is_not_a_tv_client(self) -> None:
        desktop = self.write_json("desktop.json", {"installed": {
            "client_id": TV_ID, "client_secret": TV_SECRET, "redirect_uris": ["http://localhost"],
        }})
        self.assert_failed(self.check(self.package(), webos_json=desktop), "kein TV-Client")

    def test_placeholder_json_fails(self) -> None:
        placeholder = self.write_json("placeholder.json", {"installed": {
            "client_id": "000000000000-beispiel" + SUFFIX, "client_secret": "<aus der OAuth-JSON>",
        }})
        self.assert_failed(self.check(self.package(), webos_json=placeholder), "Platzhalter")

    def test_broken_package_fails(self) -> None:
        broken = self.tmp / "broken.ipk"
        broken.write_bytes(b"kein Paket")
        self.assert_failed(self.check(broken), "kein ar-Archiv")

    # MARK: - Vergleich mit dem getesteten Build

    def reference(self, script: bytes) -> Path:
        dist = self.tmp / f"dist-{len(list(self.tmp.glob('dist-*')))}"
        (dist / "assets").mkdir(parents=True)
        (dist / "index.html").write_bytes(b'<script defer src="./assets/index-ZyXw9876.js"></script>')
        (dist / "assets/index-ZyXw9876.js").write_bytes(script)
        (dist / "appinfo.json").write_bytes(b'{"id": "tv.nori.app", "version": "9.9.9"}')
        return dist

    def test_package_equal_to_tested_build_except_credentials_passes(self) -> None:
        errors, passed = self.check(self.package(), reference=self.reference(bundle(client_id="", secret="")))
        self.assertEqual(errors, [])
        self.assertIn("Paket entspricht dem getesteten Build bis auf die Google-TV-Zugangsdaten", passed)

    def test_package_differing_beyond_credentials_fails(self) -> None:
        tested = bundle(client_id="", secret="").replace(b"window.nori", b"window.other")
        self.assert_failed(self.check(self.package(), reference=self.reference(tested)), "über die Zugangsdaten hinaus")

    def test_package_with_extra_file_fails_comparison(self) -> None:
        result = self.check(self.package(extra={"assets/new.js": b"1"}), reference=self.reference(bundle(client_id="", secret="")))
        self.assert_failed(result, "nur im Paket")


if __name__ == "__main__":
    unittest.main(verbosity=2)
