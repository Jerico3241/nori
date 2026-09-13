#!/usr/bin/env python3
"""Die lokale Google-OAuth-Konfiguration von Nori schreiben und prüfen.

Nori benutzt drei OAuth-Clients desselben Google-Cloud-Projekts, je Plattform
einen. Keiner ihrer Werte steht im Repository; sie liegen in nicht
eingecheckten Dateien, die dieses Skript schreibt:

    iOS    native/Nori-iOS/Config/Google.local.xcconfig     GOOGLE_CLIENT_ID
    macOS  native/Nori-macOS/Config/Google.local.xcconfig   GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
    webOS  apps/webos/.env.local                            VITE_NORI_GOOGLE_TV_CLIENT_ID, VITE_NORI_GOOGLE_TV_CLIENT_SECRET

Quellen:

    iOS    --ios-client-id, sonst ~/.config/nori/secrets/google-ios-client-id
           (eine Zeile; der iOS-Client hat kein Secret und keine JSON)
    macOS  ~/.config/nori/secrets/google-macos-oauth.json   (Typ „Desktop-App")
    webOS  ~/.config/nori/secrets/google-webos-oauth.json   (Typ „TVs and Limited Input devices")

Aufrufe:

    python3 tools/configure-google-oauth.py --ios --ios-client-id <ID>
    python3 tools/configure-google-oauth.py --ios              # aus ~/.config/nori/secrets
    python3 tools/configure-google-oauth.py --macos
    python3 tools/configure-google-oauth.py --webos
    python3 tools/configure-google-oauth.py --check
    python3 tools/configure-google-oauth.py --check \\
        --inspect-ios <Nori.app> --inspect-macos <Nori.app> --inspect-webos <.ipk>
    python3 tools/configure-google-oauth.py --verify-ios-app <Nori.app>
    python3 tools/configure-google-oauth.py --verify-ios-ipa <Nori.ipa>

`--check` prüft, dass die lokalen Dateien von Git ignoriert und nicht
verfolgt werden, dass die drei Client-IDs verschieden sind und dass kein
Secret-Wert im Index, in den verfolgten Dateien oder in den Commits seit
`origin/main` steht. `--inspect-*` sieht in fertige Builds und prüft, dass
jede Plattform genau ihre eigene Client-ID enthält und keine fremde.

`--verify-ios-app` und `--verify-ios-ipa` prüfen ein verteilbares iOS-Paket
ohne lokale Vergleichsdatei: `GoogleClientID` in der `Info.plist` muss
vorhanden, nicht leer und eine Google-Client-ID sein, und im Bündel darf kein
Client-Secret stehen. Die IPA wird dafür selbst entpackt — geprüft wird, was
ausgeliefert wird, nicht eine Build-Einstellung. Der Workflow `Package iOS IPA`
bricht damit ab, statt eine Fassung ohne Google-Abgleich hochzuladen.

Im CI-Protokoll (`CI` gesetzt) erscheinen Client-IDs nur als Form, nie im Wortlaut.

**Secrets werden nie ausgegeben** — weder beim Schreiben noch beim Prüfen.
Gemeldet wird höchstens „vorhanden" oder „gefunden in <Datei>".

Exit-Code 1 bei einem Fehler, 0 sonst.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import stat
import subprocess
import sys
import plistlib
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SECRETS = Path.home() / ".config/nori/secrets"

IOS_LOCAL = ROOT / "native/Nori-iOS/Config/Google.local.xcconfig"
MAC_LOCAL = ROOT / "native/Nori-macOS/Config/Google.local.xcconfig"
WEBOS_LOCAL = ROOT / "apps/webos/.env.local"

MAC_JSON = SECRETS / "google-macos-oauth.json"
WEBOS_JSON = SECRETS / "google-webos-oauth.json"
IOS_ID_FILE = SECRETS / "google-ios-client-id"

SUFFIX = ".apps.googleusercontent.com"
CLIENT_ID = re.compile(r"^\d+-[a-z0-9]+" + re.escape(SUFFIX) + r"$")
ANY_CLIENT_ID = re.compile(r"\d{6,}-[a-z0-9]{20,}" + re.escape(SUFFIX))

SECRET_PATTERN = re.compile("GOCSPX" + r"-[A-Za-z0-9_-]{10,}")
IN_CI = bool(os.environ.get("CI"))

problems: list[str] = []


def shown(client_id: str) -> str:
    """Die Client-ID für die Ausgabe — im CI-Protokoll nur ihre Form."""
    return "…" + SUFFIX if IN_CI else client_id


def fail(message: str) -> None:
    problems.append(message)
    print(f"FEHLER  {message}")


def ok(message: str) -> None:
    print(f"ok      {message}")


# MARK: - Lesen


def read_json_client(path: Path, label: str) -> tuple[str, str] | None:
    """`installed.client_id` und `installed.client_secret` — sonst nichts."""
    if not path.is_file():
        fail(f"{label}: {path} fehlt")
        return None
    mode = path.stat().st_mode
    if mode & (stat.S_IRWXG | stat.S_IRWXO):
        print(f"Hinweis {label}: {path} ist für andere Benutzer lesbar (chmod 600 empfohlen)")
    try:
        installed = json.loads(path.read_text(encoding="utf-8"))["installed"]
        client_id = str(installed["client_id"]).strip()
        secret = str(installed["client_secret"]).strip()
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        fail(f"{label}: {path.name} hat nicht die erwartete Form ({type(error).__name__})")
        return None
    if not CLIENT_ID.match(client_id):
        fail(f"{label}: client_id in {path.name} sieht nicht nach einer Google-Client-ID aus")
        return None
    if not secret or re.search(r"\s", secret):
        fail(f"{label}: client_secret in {path.name} ist leer oder enthält Leerraum")
        return None
    return client_id, secret


def read_assignments(path: Path) -> dict[str, str]:
    """`NAME = wert` (xcconfig) oder `NAME=wert` (.env) — ohne Kommentare."""
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(("//", "#")):
            continue
        name, sep, value = stripped.partition("=")
        if sep:
            values[name.strip()] = value.strip()
    return values


# MARK: - Schreiben


def safe_value(value: str, label: str) -> bool:
    # `//` beginnt in einer xcconfig einen Kommentar, `$(` eine Ersetzung.
    if "//" in value or "$" in value or '"' in value or re.search(r"\s", value):
        fail(f"{label}: Wert enthält Zeichen, die in einer Build-Konfiguration nicht stehen dürfen")
        return False
    return True


def write_private(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.chmod(path, 0o600)


HEADER = (
    "// Geschrieben von tools/configure-google-oauth.py. Nicht einchecken —\n"
    "// die Datei steht in .gitignore. Werte nie in eine andere Datei kopieren.\n\n"
)


def write_ios(client_id: str) -> None:
    if not CLIENT_ID.match(client_id):
        fail("iOS: --ios-client-id sieht nicht nach einer Google-Client-ID aus")
        return
    if not safe_value(client_id, "iOS"):
        return
    write_private(IOS_LOCAL, HEADER + "// Nur der iOS-Client (Bundle-ID to.nori.ios). Kein Client-Secret.\n"
                  f"GOOGLE_CLIENT_ID = {client_id}\n")
    ok(f"iOS: {IOS_LOCAL.relative_to(ROOT)} geschrieben (Client-ID {shown(client_id)})")


def write_macos(json_path: Path) -> None:
    client = read_json_client(json_path, "macOS")
    if not client:
        return
    client_id, secret = client
    if not (safe_value(client_id, "macOS") and safe_value(secret, "macOS")):
        return
    write_private(MAC_LOCAL, HEADER + "// Nur der macOS-Client (Typ „Desktop-App\").\n"
                  f"GOOGLE_CLIENT_ID = {client_id}\n"
                  f"GOOGLE_CLIENT_SECRET = {secret}\n")
    ok(f"macOS: {MAC_LOCAL.relative_to(ROOT)} geschrieben (Client-ID {shown(client_id)}, Client-Secret vorhanden)")


def write_webos(json_path: Path) -> None:
    client = read_json_client(json_path, "webOS")
    if not client:
        return
    client_id, secret = client
    keep = []
    if WEBOS_LOCAL.is_file():
        keep = [line for line in WEBOS_LOCAL.read_text(encoding="utf-8").splitlines()
                if not line.startswith(("VITE_NORI_GOOGLE_TV_CLIENT_ID=", "VITE_NORI_GOOGLE_TV_CLIENT_SECRET="))]
    lines = keep + [f"VITE_NORI_GOOGLE_TV_CLIENT_ID={client_id}", f"VITE_NORI_GOOGLE_TV_CLIENT_SECRET={secret}"]
    write_private(WEBOS_LOCAL, "\n".join(lines) + "\n")
    ok(f"webOS: {WEBOS_LOCAL.relative_to(ROOT)} geschrieben (Client-ID {shown(client_id)}, Client-Secret vorhanden)")


# MARK: - Prüfen


def git(*args: str, input_text: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, input=input_text)


def check_ignored() -> None:
    for path in (IOS_LOCAL, MAC_LOCAL, WEBOS_LOCAL):
        rel = str(path.relative_to(ROOT))
        if git("ls-files", "--error-unmatch", rel).returncode == 0:
            fail(f"{rel} wird von Git verfolgt — sofort mit `git rm --cached {rel}` herausnehmen")
        elif git("check-ignore", "-q", rel).returncode != 0:
            fail(f"{rel} wird von .gitignore nicht erfasst")
        else:
            ok(f"{rel} ist ignoriert und nicht verfolgt")
    for name in ("google-macos-oauth.json", "google-webos-oauth.json", "client_secret_123.json"):
        if git("check-ignore", "-q", name).returncode != 0:
            fail(f"eine Datei namens {name} würde nicht ignoriert")
    tracked_json = [line for line in git("ls-files").stdout.splitlines()
                    if re.search(r"(client_secret[^/]*|google-[^/]*-oauth)\.json$", line)]
    if tracked_json:
        fail(f"OAuth-JSON im Repository verfolgt: {', '.join(tracked_json)}")
    else:
        ok("keine OAuth-JSON im Repository")


def local_ids() -> dict[str, str]:
    ids = {
        "iOS": read_assignments(IOS_LOCAL).get("GOOGLE_CLIENT_ID", ""),
        "macOS": read_assignments(MAC_LOCAL).get("GOOGLE_CLIENT_ID", ""),
        "webOS": read_assignments(WEBOS_LOCAL).get("VITE_NORI_GOOGLE_TV_CLIENT_ID", ""),
    }
    return {platform: value for platform, value in ids.items() if value}


def secret_values() -> dict[str, str]:
    """Alle bekannten Secret-Werte, nach Herkunft. Werden nie ausgegeben."""
    values: dict[str, str] = {}
    for label, path in (("macOS-JSON", MAC_JSON), ("webOS-JSON", WEBOS_JSON)):
        if path.is_file():
            try:
                values[label] = json.loads(path.read_text(encoding="utf-8"))["installed"]["client_secret"]
            except Exception:
                pass
    mac = read_assignments(MAC_LOCAL).get("GOOGLE_CLIENT_SECRET")
    if mac:
        values["macOS-xcconfig"] = mac
    tv = read_assignments(WEBOS_LOCAL).get("VITE_NORI_GOOGLE_TV_CLIENT_SECRET")
    if tv:
        values["webOS-.env.local"] = tv
    return {label: value for label, value in values.items() if len(value) >= 8}


def check_ids() -> None:
    ids = local_ids()
    for platform in ("iOS", "macOS", "webOS"):
        if platform in ids:
            ok(f"{platform}: Client-ID {shown(ids[platform])}")
        else:
            print(f"Hinweis {platform}: keine lokale Client-ID — dieser Build hätte keinen Google-Abgleich")
    seen: dict[str, str] = {}
    for platform, value in ids.items():
        if value in seen:
            fail(f"{platform} und {seen[value]} benutzen dieselbe Client-ID")
        seen[value] = platform
    projects = {value.split("-", 1)[0] for value in ids.values()}
    if len(projects) > 1:
        fail(f"die Client-IDs stammen aus verschiedenen Cloud-Projekten ({', '.join(sorted(projects))}) — "
             "dann sehen die Geräte verschiedene appDataFolder")
    if MAC_JSON.is_file() and "macOS" in ids:
        client = read_json_client(MAC_JSON, "macOS")
        if client and client[0] != ids["macOS"]:
            fail("macOS: Client-ID in Google.local.xcconfig passt nicht zur macOS-JSON")
        if client and read_assignments(MAC_LOCAL).get("GOOGLE_CLIENT_SECRET") != client[1]:
            fail("macOS: Client-Secret in Google.local.xcconfig passt nicht zur macOS-JSON")
    if WEBOS_JSON.is_file() and "webOS" in ids:
        client = read_json_client(WEBOS_JSON, "webOS")
        if client and client[0] != ids["webOS"]:
            fail("webOS: Client-ID in .env.local passt nicht zur webOS-JSON")
    if read_assignments(IOS_LOCAL).get("GOOGLE_CLIENT_SECRET"):
        fail("iOS: Google.local.xcconfig enthält ein Client-Secret — der iOS-Client hat keines")


def check_no_secrets_in_git() -> None:
    secrets = secret_values()
    locations = {
        "verfolgte Dateien": ["grep", "-I", "-l", "-F", "-f", "-"],
        "Index": ["grep", "--cached", "-I", "-l", "-F", "-f", "-"],
    }
    for label, value in secrets.items():
        for where, args in locations.items():
            found = git(*args, input_text=value + "\n").stdout.split()
            if found:
                fail(f"Secret ({label}) steht in {where}: {', '.join(found)}")
        base = "origin/main" if git("rev-parse", "--verify", "-q", "origin/main").returncode == 0 else None
        if base:
            log = git("log", "-p", f"{base}..HEAD").stdout
            if value in log:
                fail(f"Secret ({label}) steht in einem Commit seit {base}")
    if secrets:
        ok(f"{len(secrets)} bekannte Secret-Werte weder in verfolgten Dateien, Index noch neuen Commits")
    pattern = git("grep", "-I", "-l", "-E", SECRET_PATTERN.pattern).stdout.split()
    staged = git("grep", "--cached", "-I", "-l", "-E", SECRET_PATTERN.pattern).stdout.split()
    if pattern or staged:
        fail(f"Zeichenkette im Format eines Google-Client-Secrets gefunden: {', '.join(sorted(set(pattern + staged)))}")
    else:
        ok("kein Wert im Format GOCSPX-… in verfolgten Dateien oder im Index")
    tokens = git("grep", "-I", "-l", "-E", r"ya29\.[A-Za-z0-9_-]{20,}|1//0[A-Za-z0-9_-]{20,}").stdout.split()
    if tokens:
        fail(f"etwas im Format eines Google-Tokens gefunden: {', '.join(tokens)}")
    else:
        ok("kein Access- oder Refresh-Token-Muster in verfolgten Dateien")


# MARK: - Fertige Builds


def artifact_text(path: Path) -> str:
    """Alles Lesbare eines Builds als ein Text — Info.plist, Binärstrings, Bündel."""
    chunks: list[str] = []
    if path.suffix == ".ipk":
        import shutil
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["ar", "x", str(path.resolve())], cwd=tmp, check=True)
            data = next(Path(tmp).glob("data.tar.*"))
            with tarfile.open(data) as archive:
                for member in archive.getmembers():
                    if member.isfile():
                        chunks.append(archive.extractfile(member).read().decode("utf-8", "replace"))
            shutil.rmtree(tmp, ignore_errors=True)
        return "\n".join(chunks)
    for file in path.rglob("*"):
        if file.is_file() and file.stat().st_size < 64 * 1024 * 1024:
            raw = file.read_bytes()
            if file.name == "Info.plist" and raw.startswith(b"bplist"):
                converted = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", str(file)],
                                           capture_output=True)
                raw = converted.stdout
            chunks.append(raw.decode("utf-8", "replace"))
    return "\n".join(chunks)


def inspect(platform: str, path: Path) -> None:
    if not path.exists():
        fail(f"{platform}-Build {path} fehlt")
        return
    ids = local_ids()
    text = artifact_text(path)
    expected = ids.get(platform)
    found = set(ANY_CLIENT_ID.findall(text))
    if not expected:
        fail(f"{platform}: keine lokale Client-ID zum Vergleich")
    elif expected in found:
        ok(f"{platform}-Build enthält die eigene Client-ID {shown(expected)}")
    else:
        fail(f"{platform}-Build enthält die eigene Client-ID nicht")
    for other, value in ids.items():
        if other != platform and value in found:
            fail(f"{platform}-Build enthält die Client-ID von {other}")
    foreign = found - set(ids.values())
    if foreign:
        fail(f"{platform}-Build enthält {len(foreign)} unbekannte Client-ID(s)")
    secrets = secret_values()
    own = {"macOS": ("macOS-JSON", "macOS-xcconfig"), "webOS": ("webOS-JSON", "webOS-.env.local")}.get(platform, ())
    own_values = {value for label, value in secrets.items() if label in own}
    if own_values:
        present = any(value in text for value in own_values)
        (ok if present else fail)(f"{platform}-Build: eigenes Client-Secret {'vorhanden' if present else 'fehlt'}")
    for label, value in secrets.items():
        if label not in own and value not in own_values and value in text:
            fail(f"{platform}-Build enthält ein fremdes Secret ({label})")
    if platform == "iOS" and not any(value in text for value in secrets.values()):
        ok("iOS-Build enthält kein Client-Secret")


# MARK: - Verteilbares iOS-Paket


def read_ios_id_file(path: Path) -> str | None:
    """Die iOS-Client-ID aus der Datei neben den OAuth-JSON — eine Zeile."""
    if not path.is_file():
        fail(f"iOS: {path} fehlt — dort liegt die iOS-Client-ID für Paket-Builds "
             "(eine Zeile, kein Secret, nicht im Repository)")
        return None
    if path.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        print(f"Hinweis iOS: {path} ist für andere Benutzer lesbar (chmod 600 empfohlen)")
    value = path.read_text(encoding="utf-8").strip()
    if not CLIENT_ID.match(value):
        fail(f"iOS: {path.name} enthält keine Google-Client-ID")
        return None
    return value


def known_ios_id() -> str | None:
    """Die erwartete iOS-Client-ID, falls sich eine ohne Fehlermeldung finden lässt."""
    if IOS_ID_FILE.is_file():
        value = IOS_ID_FILE.read_text(encoding="utf-8").strip()
        if CLIENT_ID.match(value):
            return value
    value = read_assignments(IOS_LOCAL).get("GOOGLE_CLIENT_ID", "")
    return value if CLIENT_ID.match(value) else None


def verify_ios_bundle(app: Path, label: str) -> None:
    """Ein fertiges `Nori.app` für iOS: eigene Client-ID vorhanden, kein Secret."""
    plist = app / "Info.plist"
    if not plist.is_file():
        fail(f"{label}: Info.plist fehlt")
        return
    try:
        info = plistlib.loads(plist.read_bytes())
    except Exception as error:
        fail(f"{label}: Info.plist nicht lesbar ({type(error).__name__})")
        return

    before = len(problems)
    value = info.get("GoogleClientID")
    if value is None:
        fail(f"{label}: GoogleClientID fehlt in der Info.plist")
    elif not isinstance(value, str) or not value.strip():
        fail(f"{label}: GoogleClientID ist leer — diese Fassung hätte keinen Google-Abgleich")
    elif "$(" in value:
        fail(f"{label}: GoogleClientID ist ein unaufgelöster Platzhalter")
    elif not value.endswith(SUFFIX):
        fail(f"{label}: GoogleClientID endet nicht auf {SUFFIX}")
    elif not CLIENT_ID.match(value):
        fail(f"{label}: GoogleClientID hat nicht die Form einer Google-Client-ID")
    else:
        expected = known_ios_id()
        if expected and value != expected:
            fail(f"{label}: GoogleClientID ist nicht die iOS-Client-ID dieses Rechners")
    if len(problems) == before:
        print("Google OAuth: configured")
        ok(f"{label}: GoogleClientID vorhanden ({shown(value)})")

    before = len(problems)
    if info.get("GoogleClientSecret"):
        fail(f"{label}: Info.plist enthält GoogleClientSecret — der iOS-Client hat keines")
    text = artifact_text(app)
    if SECRET_PATTERN.search(text):
        fail(f"{label}: Zeichenkette im Format eines Google-Client-Secrets im Bündel")
    for origin, secret in secret_values().items():
        if secret in text:
            fail(f"{label}: Bündel enthält ein Client-Secret ({origin})")
    foreign = set(ANY_CLIENT_ID.findall(text)) - ({value} if isinstance(value, str) else set())
    if foreign:
        fail(f"{label}: Bündel enthält {len(foreign)} fremde Client-ID(s)")
    if len(problems) == before:
        print("Google Client-Secret: not included")
        ok(f"{label}: kein Client-Secret und keine fremde Client-ID im Bündel")


def verify_ios_ipa(ipa: Path) -> None:
    """Die IPA selbst entpacken und das darin liegende Programm prüfen."""
    if not ipa.is_file():
        fail(f"IPA {ipa} fehlt")
        return
    with tempfile.TemporaryDirectory() as tmp:
        try:
            with zipfile.ZipFile(ipa) as archive:
                for name in archive.namelist():
                    parts = Path(name).parts
                    if name.startswith("/") or ".." in parts:
                        fail(f"IPA {ipa.name}: unzulässiger Pfad im Archiv")
                        return
                archive.extractall(tmp)
        except zipfile.BadZipFile:
            fail(f"IPA {ipa.name}: kein gültiges ZIP-Archiv")
            return
        apps = sorted(Path(tmp, "Payload").glob("*.app"))
        if len(apps) != 1:
            fail(f"IPA {ipa.name}: erwartet genau ein Programm unter Payload/, gefunden {len(apps)}")
            return
        verify_ios_bundle(apps[0], f"IPA {ipa.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ios", action="store_true", help="iOS-Konfiguration schreiben")
    parser.add_argument("--ios-client-id", help="Client-ID des iOS-Clients (sonst aus --ios-client-id-file)")
    parser.add_argument("--ios-client-id-file", type=Path, default=IOS_ID_FILE)
    parser.add_argument("--macos", action="store_true", help="macOS-Konfiguration aus der JSON schreiben")
    parser.add_argument("--macos-json", type=Path, default=MAC_JSON)
    parser.add_argument("--webos", action="store_true", help="webOS-.env.local aus der JSON schreiben")
    parser.add_argument("--webos-json", type=Path, default=WEBOS_JSON)
    parser.add_argument("--check", action="store_true", help="Ignorieren, IDs und Secrets in Git prüfen")
    parser.add_argument("--inspect-ios", type=Path)
    parser.add_argument("--inspect-macos", type=Path)
    parser.add_argument("--inspect-webos", type=Path)
    parser.add_argument("--verify-ios-app", type=Path, help="fertiges iOS-Nori.app prüfen")
    parser.add_argument("--verify-ios-ipa", type=Path, help="fertige iOS-IPA entpacken und prüfen")
    args = parser.parse_args()

    if args.ios:
        if args.ios_client_id:
            write_ios(args.ios_client_id.strip())
        else:
            client_id = read_ios_id_file(args.ios_client_id_file.expanduser())
            if client_id:
                write_ios(client_id)
    if args.macos:
        write_macos(args.macos_json.expanduser())
    if args.webos:
        write_webos(args.webos_json.expanduser())

    if args.check or args.inspect_ios or args.inspect_macos or args.inspect_webos:
        check_ignored()
        check_ids()
        check_no_secrets_in_git()
    if args.inspect_ios:
        inspect("iOS", args.inspect_ios)
    if args.inspect_macos:
        inspect("macOS", args.inspect_macos)
    if args.inspect_webos:
        inspect("webOS", args.inspect_webos)
    if args.verify_ios_app:
        verify_ios_bundle(args.verify_ios_app, "iOS-Programm")
    if args.verify_ios_ipa:
        verify_ios_ipa(args.verify_ios_ipa)

    if not any((args.ios, args.macos, args.webos, args.check,
                args.inspect_ios, args.inspect_macos, args.inspect_webos,
                args.verify_ios_app, args.verify_ios_ipa)):
        parser.print_help()
        return 0
    print(f"\n{len(problems)} Fehler" if problems else "\nkeine Auffälligkeiten")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
