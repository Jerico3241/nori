#!/usr/bin/env python3
"""Die lokale Google-OAuth-Konfiguration der iOS-App schreiben und prüfen.

Nori benutzt für iPhone und iPad einen OAuth-Client. Sein Wert steht nicht im
Repository; er liegt in einer nicht eingecheckten Datei, die dieses Skript
schreibt:

    native/Nori-iOS/Config/Google.local.xcconfig     GOOGLE_CLIENT_ID

Quelle: --ios-client-id, sonst NORI_GOOGLE_IOS_CLIENT_ID, sonst
~/.config/nori/secrets/google-ios-client-id (eine Zeile; der iOS-Client hat
kein Secret und keine JSON).

Aufrufe:

    python3 tools/configure-google-oauth.py --ios --ios-client-id <ID>
    python3 tools/configure-google-oauth.py --ios              # Umgebung oder ~/.config/nori/secrets
    python3 tools/configure-google-oauth.py --check
    python3 tools/configure-google-oauth.py --check --inspect-ios <Nori.app>
    python3 tools/configure-google-oauth.py --verify-ios-app <Nori.app>
    python3 tools/configure-google-oauth.py --verify-ios-ipa <Nori.ipa>

`--check` prüft, dass die lokale Datei von Git ignoriert und nicht verfolgt
wird und dass kein Secret- oder Token-Muster in den verfolgten Dateien oder im
Index steht. `--inspect-ios` sieht in einen fertigen Build und prüft, dass er
genau die eigene Client-ID enthält und keine fremde.

`--verify-ios-app` und `--verify-ios-ipa` prüfen ein verteilbares Paket ohne
lokale Vergleichsdatei: `GoogleClientID` in der `Info.plist` muss vorhanden,
nicht leer und eine Google-Client-ID sein, und im Bündel darf kein
Client-Secret stehen. Die IPA wird dafür selbst entpackt — geprüft wird, was
ausgeliefert wird, nicht eine Build-Einstellung. Der Job `ipa` in `Build iOS`
bricht damit ab, statt eine Fassung ohne Google-Abgleich hochzuladen.

Im CI-Protokoll (`CI` gesetzt) erscheinen Client-IDs nur als Form, nie im Wortlaut.

Exit-Code 1 bei einem Fehler, 0 sonst.
"""

from __future__ import annotations

import argparse
import os
import re
import stat
import subprocess
import sys
import plistlib
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SECRETS = Path.home() / ".config/nori/secrets"

IOS_LOCAL = ROOT / "native/Nori-iOS/Config/Google.local.xcconfig"
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


def read_assignments(path: Path) -> dict[str, str]:
    """`NAME = wert` aus einer xcconfig — ohne Kommentare."""
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


def env_value(name: str) -> str:
    return os.environ.get(name, "").strip()


# MARK: - Prüfen


def git(*args: str, input_text: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, input=input_text)


def check_ignored() -> None:
    rel = str(IOS_LOCAL.relative_to(ROOT))
    if git("ls-files", "--error-unmatch", rel).returncode == 0:
        fail(f"{rel} wird von Git verfolgt — sofort mit `git rm --cached {rel}` herausnehmen")
    elif git("check-ignore", "-q", rel).returncode != 0:
        fail(f"{rel} wird von .gitignore nicht erfasst")
    else:
        ok(f"{rel} ist ignoriert und nicht verfolgt")
    for name in ("google-ios-oauth.json", "client_secret_123.json"):
        if git("check-ignore", "-q", name).returncode != 0:
            fail(f"eine Datei namens {name} würde nicht ignoriert")
    tracked_json = [line for line in git("ls-files").stdout.splitlines()
                    if re.search(r"(client_secret[^/]*|google-[^/]*-oauth)\.json$", line)]
    if tracked_json:
        fail(f"OAuth-JSON im Repository verfolgt: {', '.join(tracked_json)}")
    else:
        ok("keine OAuth-JSON im Repository")


def local_id() -> str:
    return read_assignments(IOS_LOCAL).get("GOOGLE_CLIENT_ID", "")


def check_ids() -> None:
    client_id = local_id()
    if client_id:
        ok(f"iOS: Client-ID {shown(client_id)}")
    else:
        print("Hinweis iOS: keine lokale Client-ID — dieser Build hätte keinen Google-Abgleich")
    if read_assignments(IOS_LOCAL).get("GOOGLE_CLIENT_SECRET"):
        fail("iOS: Google.local.xcconfig enthält ein Client-Secret — der iOS-Client hat keines")


def check_no_secrets_in_git() -> None:
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
    for file in path.rglob("*"):
        if file.is_file() and file.stat().st_size < 64 * 1024 * 1024:
            raw = file.read_bytes()
            # Eine Info.plist im Binärformat ist für die Textsuche unten
            # unlesbar und muss vorher nach XML. Das macht `plistlib` aus der
            # Standardbibliothek — nicht `plutil`: Das Werkzeug gibt es nur auf
            # macOS, und der Aufruf warf auf jedem anderen Rechner
            # FileNotFoundError mitten in der Prüfung. Die Suche nach fremden
            # Client-IDs und nach Client-Secrets im Bundle lief dort also nie,
            # obwohl sie der eigentliche Zweck dieser Funktion ist.
            if file.name == "Info.plist" and raw.startswith(b"bplist"):
                try:
                    raw = plistlib.dumps(plistlib.loads(raw), fmt=plistlib.FMT_XML)
                except Exception:
                    # Eine unlesbare Info.plist ist kein Grund, die Prüfung
                    # abzubrechen — die Rohbytes durchsuchen wir trotzdem.
                    pass
            chunks.append(raw.decode("utf-8", "replace"))
    return "\n".join(chunks)


def inspect(path: Path) -> None:
    if not path.exists():
        fail(f"iOS-Build {path} fehlt")
        return
    expected = local_id()
    text = artifact_text(path)
    found = set(ANY_CLIENT_ID.findall(text))
    if not expected:
        fail("iOS: keine lokale Client-ID zum Vergleich")
    elif expected in found:
        ok(f"iOS-Build enthält die eigene Client-ID {shown(expected)}")
    else:
        fail("iOS-Build enthält die eigene Client-ID nicht")
    foreign = found - {expected}
    if foreign:
        fail(f"iOS-Build enthält {len(foreign)} unbekannte Client-ID(s)")
    if SECRET_PATTERN.search(text):
        fail("iOS-Build enthält eine Zeichenkette im Format eines Google-Client-Secrets")
    else:
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
    parser.add_argument("--check", action="store_true", help="Ignorieren, ID und Secrets in Git prüfen")
    parser.add_argument("--inspect-ios", type=Path)
    parser.add_argument("--verify-ios-app", type=Path, help="fertiges iOS-Nori.app prüfen")
    parser.add_argument("--verify-ios-ipa", type=Path, help="fertige iOS-IPA entpacken und prüfen")
    args = parser.parse_args()

    if args.ios:
        if args.ios_client_id:
            write_ios(args.ios_client_id.strip())
        elif env_value("NORI_GOOGLE_IOS_CLIENT_ID"):
            write_ios(env_value("NORI_GOOGLE_IOS_CLIENT_ID"))
        else:
            client_id = read_ios_id_file(args.ios_client_id_file.expanduser())
            if client_id:
                write_ios(client_id)

    if args.check or args.inspect_ios:
        check_ignored()
        check_ids()
        check_no_secrets_in_git()
    if args.inspect_ios:
        inspect(args.inspect_ios)
    if args.verify_ios_app:
        verify_ios_bundle(args.verify_ios_app, "iOS-Programm")
    if args.verify_ios_ipa:
        verify_ios_ipa(args.verify_ios_ipa)

    if not any((args.ios, args.check, args.inspect_ios, args.verify_ios_app, args.verify_ios_ipa)):
        parser.print_help()
        return 0
    print(f"\n{len(problems)} Fehler" if problems else "\nkeine Auffälligkeiten")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
