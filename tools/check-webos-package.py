#!/usr/bin/env python3
"""Statische Prüfung der webOS-App von Nori.

Vier Fragen, die sich nicht durch Hinsehen beantworten lassen:

1. Steckt in Quelltext oder Paket etwas von der Referenz-App? Weder Name noch
   Marke noch ein Aufruf ihres Dienstes darf in Nori landen. Die Referenz durfte
   für Bedienkonzepte angesehen werden, für nichts sonst.
2. Ist `appinfo.json` gültig? webOS lehnt ein Paket mit einem unbekannten Feld
   nicht ab — es ignoriert es. Ein Tippfehler fällt sonst erst auf dem Fernseher
   auf, und auch dort nur als „tut nichts".
3. **Stimmen die Versionsnummern überein?** `appinfo.json`, `package.json`, der
   Dateiname des Pakets, die Datei darin und der Changelog müssen dieselbe
   Nummer tragen. Zwei Pakete mit derselben Nummer, aber unterschiedlichem
   Inhalt, sind hinterher nicht mehr unterscheidbar — und der Fernseher
   installiert das zweite nicht über das erste.
4. **Läuft das Paket von `file://`?** Eine Adresse mit führendem Schrägstrich
   (`/assets/index.js`) zeigt dort auf die Wurzel des Dateisystems. Im
   Entwicklungsstand über HTTP fällt das nie auf, auf dem Fernseher bleibt der
   Bildschirm schwarz.
5. **Steckt ein Schlüssel im Quelltext?** Genau einer darf: der mitgelieferte
   TMDB-Schlüssel in `shared/nori-core/src/tmdb/key.ts`. Das ist dieselbe
   Ausnahme, die `tools/check-apple-sources.py` für `TMDBKeyStore.builtIn`
   kennt — vom Betreiber entschieden, für eine private App in einem privaten
   Repository. Jeder **zweite** einkompilierte Schlüssel fällt weiterhin auf,
   auch einer in derselben Datei.

6. **Trägt das Paket die richtigen Google-Zugangsdaten — und nur die?** Nach
   jedem Paket gilt: keine `.env*`, keine OAuth-JSON, keine Tokens,
   Gerätecodes oder Cookies. Mit `--production` zusätzlich: genau die
   Client-ID und das Secret aus `~/.config/nori/secrets/google-webos-oauth.json`
   liegen im Paket, und keine anderen — weder iOS noch macOS noch ältere
   Test-Clients aus demselben Ordner. Geprüft wird das fertige `.ipk` selbst,
   entpackt, jede Datei als Bytes. Werte werden nie ausgegeben.

    python3 tools/check-webos-package.py
    python3 tools/check-webos-package.py --production [--ipk <paket>] [--reference-dist <ordner>]

`--reference-dist` vergleicht das Paket mit einem ohne Zugangsdaten gebauten
`dist/` — dem, gegen den der Fernbedienungslauf lief. Jede Datei muss gleich
sein; Unterschiede sind nur an genau den beiden Zugangsdaten erlaubt.

Exit-Code 1 bei ERROR, 0 sonst. Ergänzt `tools/check-apple-sources.py`, das
dieselbe Aufgabe für die beiden Apple-Targets übernimmt.
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps/webos"
CORE = ROOT / "shared/nori-core"
API = ROOT / "services/nori-api"

# Dateien, die im Paket liegen müssen. Ohne die Symbole installiert sich das
# Paket und erscheint auf dem Fernseher als weiße Fläche im Launcher. Ohne
# `vendor/hls.min.js` startet die App, aber kein HLS-Stream auf einem Gerät
# ohne natives HLS — hls.js wird erst im Player nachgeladen.
REQUIRED_ASSETS = ["icon-80.png", "icon-130.png", "splash-1920x1080.png", "vendor/hls.min.js"]

# Namen und Kennungen der Referenz-App. Groß-/Kleinschreibung egal.
FOREIGN_NAMES = ["fireanime", "fireani", "animecloud", "fireani.me"]

# Adressen, die eine Nori-App nie abrufen darf.
FOREIGN_HOSTS = [
    r"fireani\.me",
    r"api\.fireani\.me",
    r"animecloud\.[a-z]{2,}",
    r"tv\.animecloud\.",
]

# Felder, die webOS in appinfo.json kennt. Quelle: die Referenz für webOS-TV-
# Web-Apps von LG. Was nicht hier steht, wird beanstandet — lieber eine Zeile
# mehr in dieser Liste als ein Feld, das stillschweigend nichts tut.
KNOWN_APPINFO = {
    "id", "version", "vendor", "type", "main", "title", "appDescription",
    "icon", "largeIcon", "iconColor", "bgColor", "bgImage", "splashBackground",
    "splashColor", "resolution", "disableBackHistoryAPI", "handlesRelaunch",
    "transparent", "supportPortraitMode", "supportTouchMode", "requiredMemory",
    "closeOnRotation", "useGalleryMode", "virtualTouch", "accessibility",
    "allowVideoCapture", "allowAudioCapture", "hiddenAppInFullScreenMode",
    "inspectable", "noWindow", "requiredPermissions", "uiRevision",
}

REQUIRED_APPINFO = {"id", "version", "vendor", "type", "main", "title", "icon"}

# Dateien, die geprüft werden. `node_modules` und Bauordner bleiben außen vor:
# dort steht fremder Code, den Nori nicht schreibt, und die Suche liefe sonst
# minutenlang.
SOURCE_GLOBS = ["**/*.ts", "**/*.tsx", "**/*.css", "**/*.html", "**/*.json", "**/*.mjs"]
SKIP_PARTS = {"node_modules", "dist", ".git", "package-lock.json"}

# Google-Zugangsdaten. Die Muster sind zusammengesetzt, damit dieses Werkzeug
# selbst nicht wie ein eingecheckter Wert aussieht.
SECRETS_DIR = Path.home() / ".config/nori/secrets"
WEBOS_JSON = SECRETS_DIR / "google-webos-oauth.json"
CLIENT_ID_SUFFIX = ".apps.googleusercontent.com"
CLIENT_ID_EXACT = re.compile(r"^\d+-[a-z0-9]+" + re.escape(CLIENT_ID_SUFFIX) + r"$")
CLIENT_ID_ANY = re.compile((r"\d{6,}-[a-z0-9]{20,}" + re.escape(CLIENT_ID_SUFFIX)).encode())
SECRET_ANY = re.compile(("GOCSPX" + r"-[A-Za-z0-9_-]{10,}").encode())
PLACEHOLDER = re.compile(r"[<>]|beispiel|example|placeholder|platzhalter|changeme|nie einchecken|^0+-", re.IGNORECASE)
TOKEN_PATTERNS = [
    (re.compile(("ya" + r"29\.[A-Za-z0-9_-]{20,}").encode()), "Access-Token"),
    (re.compile(("1/" + r"/0[A-Za-z0-9_-]{20,}").encode()), "Refresh-Token"),
    (re.compile(rb'"(?:access_token|refresh_token|id_token|device_code|user_code)"\s*:\s*"[^"\s]{8,}"'), "Token oder Gerätecode als Wert"),
    (re.compile(rb"Set-Cookie:|cf_clearance=|__Secure-[0-9A-Za-z]*PSID="), "Cookie"),
]
FORBIDDEN_FILES = re.compile(
    r"(^|/)(\.env(\.[^/]*)?|client_secret[^/]*\.json|[^/]*oauth[^/]*\.json|google-services\.json|GoogleService-Info\.plist)$",
    re.IGNORECASE,
)

problems: list[str] = []
warnings: list[str] = []
notes: list[str] = []


def sources() -> list[Path]:
    files: list[Path] = []
    for base in (APP, CORE, API):
        if not base.exists():
            continue
        for pattern in SOURCE_GLOBS:
            for path in base.glob(pattern):
                if any(part in SKIP_PARTS for part in path.parts):
                    continue
                files.append(path)
    return sorted(set(files))


def check_foreign_names() -> None:
    """Kein fremder Name, keine fremde Marke, kein fremdes Kürzel im Quelltext."""
    pattern = re.compile("|".join(re.escape(name) for name in FOREIGN_NAMES), re.IGNORECASE)
    for path in sources():
        text = path.read_text(encoding="utf-8", errors="replace")
        for number, line in enumerate(text.splitlines(), 1):
            if pattern.search(line):
                rel = path.relative_to(ROOT)
                problems.append(f"{rel}:{number}: Name der Referenz-App im Quelltext — {line.strip()[:90]}")


def check_foreign_hosts() -> None:
    """Kein Abruf gegen einen fremden Dienst."""
    pattern = re.compile("|".join(FOREIGN_HOSTS), re.IGNORECASE)
    for path in sources():
        text = path.read_text(encoding="utf-8", errors="replace")
        for number, line in enumerate(text.splitlines(), 1):
            if pattern.search(line):
                rel = path.relative_to(ROOT)
                problems.append(f"{rel}:{number}: Adresse eines fremden Dienstes — {line.strip()[:90]}")


def check_appinfo() -> None:
    path = APP / "appinfo.json"
    if not path.exists():
        problems.append("apps/webos/appinfo.json fehlt")
        return
    try:
        info = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        problems.append(f"apps/webos/appinfo.json ist kein gültiges JSON: {error}")
        return

    missing = REQUIRED_APPINFO - info.keys()
    if missing:
        problems.append(f"appinfo.json: Pflichtfelder fehlen — {', '.join(sorted(missing))}")

    unknown = info.keys() - KNOWN_APPINFO
    if unknown:
        problems.append(
            "appinfo.json: unbekannte Felder — "
            f"{', '.join(sorted(unknown))} (webOS ignoriert sie stillschweigend)"
        )

    if info.get("type") != "web":
        problems.append(f"appinfo.json: `type` muss \"web\" sein, ist {info.get('type')!r}")

    app_id = info.get("id", "")
    if not re.fullmatch(r"[a-z0-9]+(\.[a-z0-9]+)+", app_id):
        problems.append(f"appinfo.json: `id` {app_id!r} ist keine gültige umgekehrte Domain")
    if "fireani" in app_id or "animecloud" in app_id:
        problems.append(f"appinfo.json: `id` {app_id!r} übernimmt eine fremde Kennung")

    if not re.fullmatch(r"\d+\.\d+\.\d+", str(info.get("version", ""))):
        problems.append(f"appinfo.json: `version` {info.get('version')!r} ist nicht x.y.z")

    for field in ("icon", "largeIcon", "splashBackground"):
        name = info.get(field)
        if name and not (APP / "public" / name).exists():
            problems.append(f"appinfo.json: `{field}` verweist auf {name}, das es in public/ nicht gibt")


def check_no_secrets() -> None:
    """Kein Schlüssel im Quelltext — mit einer benannten Ausnahme.

    Ein Schlüssel im Quelltext liegt in jedem Klon, in jedem Build und dauerhaft
    in der Git-Historie; wer ihn sperrt, sperrt alle Installationen zugleich.
    Beim webOS-Paket kommt hinzu, dass er im `.ipk` liegt und sich daraus
    herausziehen lässt.

    Die eine Ausnahme ist der mitgelieferte TMDB-Schlüssel in
    `shared/nori-core/src/tmdb/key.ts`. Sie ist absichtlich eng an genau diese
    Zeile geknüpft: ein zweiter Schlüssel in derselben Datei fällt auf, ein
    Schlüssel in einer anderen Datei ebenfalls. Auf einem Fernseher gibt es
    keine Tastatur — die Begründung steht an der Deklaration.
    """
    long_hex = re.compile(r'"[0-9a-f]{32,}"')
    named = re.compile(
        r'\b(?:apiKey|api_key|apiSecret|clientSecret|accessToken|refreshToken|password)\b'
        r'\s*(?:=|:)\s*"[^"\n]{8,}"',
        re.IGNORECASE,
    )
    allowed_file = CORE / "src/tmdb/key.ts"
    allowed_line = re.compile(r'export const BUILT_IN_TMDB_KEY = "[0-9a-f]{32}";')

    for path in sources():
        if path.suffix not in {".ts", ".tsx", ".mjs"}:
            continue
        raw = path.read_text(encoding="utf-8", errors="replace")
        # Kommentare weg: eine Erklärung, die das Wort „api_key" enthält, ist
        # kein Fund. Die Zeichenketten bleiben stehen — sie sind der Fund.
        stripped = re.sub(r"//[^\n]*", " ", re.sub(r"/\*.*?\*/", " ", raw, flags=re.S))
        if path == allowed_file:
            stripped = allowed_line.sub(" ", stripped)
        rel = path.relative_to(ROOT)
        # Prüfdateien werden nur auf lange Hex-Zeichenketten gelesen, nicht auf
        # Zuweisungen an Schlüsselnamen. Der Grund ist inhaltlich: ein Test, der
        # belegt, dass `api_key` aus einer Anfrage **entfernt** wird, muss genau
        # so eine Zuweisung enthalten — sonst prüft er nichts. Ein echter
        # Schlüssel wäre weiterhin auffällig, denn er ist hexadezimal.
        patterns = [(long_hex, "lange Hex-Zeichenkette")]
        if "test" not in path.parts:
            patterns.append((named, "Zuweisung an einen Schlüsselnamen"))
        for pattern, what in patterns:
            match = pattern.search(stripped)
            if match:
                problems.append(
                    f"{rel}: {what} im Quelltext — {match.group(0)[:48]}. "
                    "Schlüssel gehören nicht in das Paket; die einzige Ausnahme ist "
                    "BUILT_IN_TMDB_KEY in shared/nori-core/src/tmdb/key.ts."
                )


def check_key_matches_apple() -> None:
    """Derselbe mitgelieferte Schlüssel wie auf der Apple-Seite.

    Zwei Kopien einer Zeichenkette laufen auseinander. Läuft diese auseinander,
    zeigt der Fernseher zu derselben Serie andere Daten als das iPhone — und
    zwar ohne Fehlermeldung, weil beide Schlüssel gültig sind.
    """
    js = CORE / "src/tmdb/key.ts"
    swift = ROOT / "native/NoriCore/Sources/NoriCore/AniworldClient.swift"
    if not js.exists() or not swift.exists():
        return
    here = re.search(r'BUILT_IN_TMDB_KEY = "([0-9a-f]{32})"', js.read_text(encoding="utf-8"))
    there = re.search(r'builtIn = "([0-9a-f]{32})"', swift.read_text(encoding="utf-8"))
    if not here or not there:
        warnings.append(
            "Der mitgelieferte TMDB-Schlüssel ließ sich nicht auf beiden Seiten finden — "
            "Abgleich übersprungen."
        )
        return
    if here.group(1) != there.group(1):
        problems.append(
            "Der mitgelieferte TMDB-Schlüssel weicht ab: "
            "shared/nori-core/src/tmdb/key.ts gegen TMDBKeyStore.builtIn. "
            "Beide Seiten müssen denselben benutzen."
        )


def check_versions() -> None:
    """Dieselbe Nummer an allen Stellen."""
    appinfo_path = APP / "appinfo.json"
    package_path = APP / "package.json"
    if not appinfo_path.exists() or not package_path.exists():
        return
    try:
        appinfo = json.loads(appinfo_path.read_text(encoding="utf-8"))
        package = json.loads(package_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return  # check_appinfo hat das schon beanstandet

    version = str(appinfo.get("version", ""))
    if str(package.get("version", "")) != version:
        problems.append(
            "Versionen weichen ab — appinfo.json "
            f"{version!r}, apps/webos/package.json {package.get('version')!r}"
        )

    changelog = ROOT / "CHANGELOG.md"
    if changelog.exists():
        text = changelog.read_text(encoding="utf-8")
        if f"[webOS {version}]" not in text:
            problems.append(
                f"CHANGELOG.md hat keinen Abschnitt `[webOS {version}]`. "
                "Ein Paket ohne Eintrag ist eines, dessen Änderungen niemand kennt."
            )
        # Die Übersicht am Anfang nennt die Stände aller Plattformen.
        if not re.search(rf"LG webOS \*\*{re.escape(version)}\*\*", text):
            warnings.append(
                f"CHANGELOG.md nennt in der Übersicht nicht `LG webOS **{version}**`."
            )

    packages = sorted(APP.glob("*.ipk"))
    expected = f"{appinfo.get('id', '')}_{version}_all.ipk"
    if packages and not any(package_file.name == expected for package_file in packages):
        problems.append(
            f"Kein Paket mit dem erwarteten Namen {expected} — "
            f"vorhanden: {', '.join(p.name for p in packages)}. "
            "Erst `npm run build && npm run webos:package`."
        )


def check_relative_paths() -> None:
    """Läuft der gebaute Stand von `file://`?

    Drei Dinge gehen dort schief, die über HTTP nie auffallen:

    * eine Adresse mit führendem Schrägstrich zeigt auf die Wurzel des
      Dateisystems,
    * `type="module"` lädt gar nicht — Chromium verweigert ES-Module von
      `file://`, weil die Seite die Herkunft `null` hat,
    * `crossorigin` macht aus einem gleichartigen Abruf einen mit
      Herkunftsprüfung, und die scheitert aus demselben Grund.

    Alle drei enden auf dem Fernseher in einem schwarzen Bildschirm ohne
    Fehlermeldung: das Skript, das den Fehler melden würde, läuft nicht.
    """
    index = APP / "dist" / "index.html"
    if not index.exists():
        return
    text = index.read_text(encoding="utf-8")
    for match in re.finditer(r'(?:src|href)="(/[^/][^"]*)"', text):
        problems.append(
            f"dist/index.html verweist absolut auf {match.group(1)} — "
            "von `file://` zeigt das auf die Wurzel des Dateisystems."
        )
    if 'type="module"' in text:
        problems.append(
            "dist/index.html lädt ein ES-Modul — von `file://` lädt Chromium "
            "keines. Das Bündel muss klassisch sein (`format: \"iife\"`)."
        )
    if "crossorigin" in text:
        problems.append(
            "dist/index.html setzt `crossorigin` — von `file://` scheitert die "
            "Herkunftsprüfung, weil die Seite die Herkunft `null` hat."
        )


def check_css_compat() -> None:
    """Keine CSS-Merkmale, die webOS 6 (Chrome 79) nicht kennt.

    Beide Fälle fallen in einem heutigen Browser nicht auf und brechen auf dem
    ältesten unterstützten Fernseher still das Layout:

    * `inset` kam mit Chrome 87 — ein Overlay ohne `top/right/bottom/left`
      liegt dort in der Ecke statt über dem Bild.
    * `aspect-ratio` kam mit Chrome 88 — eine Bildfläche ohne Höhe fällt auf
      null zusammen, und jede Karte darunter rutscht nach oben.

    Flex-`gap` (Chrome 84) lässt sich statisch nicht vom Raster-`gap`
    unterscheiden; das prüft der Fernbedienungslauf im Browser.
    """
    styles = APP / "src" / "styles"
    if not styles.exists():
        return
    forbidden = [
        (re.compile(r"(^|[;{\s])inset\s*:"), "`inset` (erst ab Chrome 87)"),
        (re.compile(r"aspect-ratio\s*:"), "`aspect-ratio` (erst ab Chrome 88)"),
    ]
    for path in sorted(styles.glob("*.css")):
        text = re.sub(r"/\*.*?\*/", " ", path.read_text(encoding="utf-8"), flags=re.S)
        for number, line in enumerate(text.splitlines(), 1):
            for pattern, what in forbidden:
                if pattern.search(line):
                    problems.append(f"{path.relative_to(ROOT)}:{number}: {what} — webOS 6 kennt es nicht")

    # Die Navigation ist eigene: ein Rest von Enact Spotlight wäre ein zweites
    # System, das dieselben Tasten abgreift.
    for path in sources():
        if path.suffix not in {".ts", ".tsx"} or APP not in path.parents:
            continue
        if "@enact/" in path.read_text(encoding="utf-8", errors="replace"):
            problems.append(f"{path.relative_to(ROOT)}: importiert Enact — die Navigation liegt in src/navigation/engine.ts")


def package_rel(package: Path) -> str:
    try:
        return str(package.resolve().relative_to(ROOT))
    except ValueError:
        return package.name


def read_ipk(package: Path) -> tuple[dict[str, bytes], list[tuple[str, bytes]]] | str:
    """ar-Archiv lesen: Teile des Pakets und alle Dateien aus Daten und Steuerung."""
    raw = package.read_bytes()
    if not raw.startswith(b"!<arch>\n"):
        return "kein ar-Archiv"
    members: dict[str, bytes] = {}
    offset = 8
    while offset + 60 <= len(raw):
        header = raw[offset:offset + 60]
        offset += 60
        name = header[0:16].decode("ascii", "replace").strip().rstrip("/")
        try:
            size = int(header[48:58].decode("ascii").strip())
        except ValueError:
            return f"unlesbare Größenangabe für {name}"
        members[name] = raw[offset:offset + size]
        offset += size + (size % 2)
    files: list[tuple[str, bytes]] = []
    for part in ("control.tar.gz", "data.tar.gz"):
        if part not in members:
            continue
        try:
            with tarfile.open(fileobj=io.BytesIO(members[part]), mode="r:gz") as archive:
                for member in archive.getmembers():
                    if member.isfile():
                        handle = archive.extractfile(member)
                        files.append((member.name, handle.read() if handle else b""))
        except (tarfile.TarError, OSError) as error:
            return f"{part} nicht lesbar ({type(error).__name__})"
    return members, files


def read_tv_client(path: Path) -> tuple[str, str] | str:
    """Client-ID und Secret des TV-Clients — oder der Grund, warum nicht."""
    if not path.is_file():
        return f"{path} fehlt"
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return f"{path.name} ist kein gültiges JSON"
    installed = document.get("installed") if isinstance(document, dict) else None
    if not isinstance(installed, dict):
        return f"{path.name}: erwartet `installed` eines TV-Clients"
    if "redirect_uris" in installed:
        return f"{path.name} ist kein TV-Client (redirect_uris vorhanden)"
    client_id = str(installed.get("client_id", "")).strip()
    secret = str(installed.get("client_secret", "")).strip()
    if not client_id:
        return f"client_id fehlt oder ist leer in {path.name}"
    if not secret:
        return f"client_secret fehlt oder ist leer in {path.name}"
    if PLACEHOLDER.search(client_id) or PLACEHOLDER.search(secret):
        return f"{path.name} enthält Platzhalter statt Zugangsdaten"
    if not CLIENT_ID_EXACT.match(client_id):
        return f"client_id in {path.name} ist keine Google-Client-ID"
    if re.search(r"\s", secret):
        return f"client_secret in {path.name} enthält Leerraum"
    return client_id, secret


def foreign_credentials(secrets_dir: Path, production_json: Path) -> dict[str, str]:
    """Alle bekannten Zugangsdaten, die **nicht** ins webOS-Paket gehören.

    Jede OAuth-JSON im Secrets-Ordner außer der produktiven — also macOS und
    ältere Test-Clients —, die iOS-Client-ID und die lokalen Apple-
    Konfigurationen. Beschriftet nach Herkunft, nie nach Wert.
    """
    found: dict[str, str] = {}
    production = production_json.resolve() if production_json.exists() else None
    if secrets_dir.is_dir():
        for path in sorted(secrets_dir.glob("*.json")):
            if production and path.resolve() == production:
                continue
            try:
                document = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError, UnicodeDecodeError):
                continue
            if not isinstance(document, dict):
                continue
            for kind, body in document.items():
                if not isinstance(body, dict):
                    continue
                for key in ("client_id", "client_secret"):
                    value = str(body.get(key, "")).strip()
                    if len(value) >= 8:
                        found[f"{path.name} ({kind}.{key})"] = value
        ios = secrets_dir / "google-ios-client-id"
        if ios.is_file():
            value = ios.read_text(encoding="utf-8").strip()
            if value:
                found["iOS-Client-ID"] = value
    for platform in ("Nori-iOS", "Nori-macOS"):
        xcconfig = ROOT / "native" / platform / "Config/Google.local.xcconfig"
        if not xcconfig.is_file():
            continue
        for line in xcconfig.read_text(encoding="utf-8").splitlines():
            name, sep, value = line.strip().partition("=")
            if sep and name.strip() in ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET") and len(value.strip()) >= 8:
                found[f"{platform} {name.strip()}"] = value.strip()
    return found


def check_package_credentials(
    package: Path,
    production: bool,
    secrets_dir: Path = SECRETS_DIR,
    webos_json: Path = WEBOS_JSON,
    reference_dist: Path | None = None,
) -> tuple[list[str], list[str]]:
    """Google-Zugangsdaten im fertigen Paket prüfen.

    Gibt Fehler und Erfolgsmeldungen zurück, ohne je einen Wert auszugeben.
    Ohne `production` nur das, was in keinem Paket stehen darf.
    """
    errors: list[str] = []
    passed: list[str] = []
    rel = package_rel(package)
    if not package.is_file():
        return [f"{rel}: Paket fehlt"], passed
    read = read_ipk(package)
    if isinstance(read, str):
        return [f"{rel}: {read}"], passed
    _, files = read

    for name, _ in files:
        if FORBIDDEN_FILES.search(name):
            errors.append(f"{rel}: Datei mit Zugangsdaten im Paket — {name}")
    for name, data in files:
        for pattern, what in TOKEN_PATTERNS:
            if pattern.search(data):
                errors.append(f"{rel}: {what} in {name}")

    if not production:
        return errors, passed

    client = read_tv_client(webos_json)
    if isinstance(client, str):
        errors.append(f"Google TV OAuth: {client}")
        return errors, passed
    client_id, secret = client

    blob_ids: set[bytes] = set()
    blob_secrets: set[bytes] = set()
    for _, data in files:
        blob_ids.update(CLIENT_ID_ANY.findall(data))
        blob_secrets.update(SECRET_ANY.findall(data))
    has_id = any(client_id.encode() in data for _, data in files)
    has_secret = any(secret.encode() in data for _, data in files)
    if has_id:
        passed.append("Google TV Client ID: valid")
    else:
        errors.append(f"{rel}: Google-TV-Client-ID fehlt im Paket — Build ohne produktive Konfiguration?")
    if has_secret:
        passed.append("Google TV Client Secret: included")
    else:
        errors.append(f"{rel}: Google-TV-Client-Secret fehlt im Paket")

    foreign_hits = []
    for label, value in foreign_credentials(secrets_dir, webos_json).items():
        if value in (client_id, secret):
            continue
        if any(value.encode() in data for _, data in files):
            foreign_hits.append(label)
    for label in foreign_hits:
        errors.append(f"{rel}: fremde Zugangsdaten im Paket — {label}")
    unknown_ids = blob_ids - {client_id.encode()}
    if unknown_ids:
        errors.append(f"{rel}: {len(unknown_ids)} weitere Client-ID(s) im Paket")
    unknown_secrets = blob_secrets - {secret.encode()}
    if unknown_secrets:
        errors.append(f"{rel}: {len(unknown_secrets)} weitere(s) Client-Secret(s) im Paket")
    if not foreign_hits and not unknown_ids and not unknown_secrets:
        passed.append("No foreign OAuth credentials found")

    if reference_dist is not None:
        errors.extend(compare_with_reference(rel, files, reference_dist, client_id, secret, passed))
        if not any("Referenz" in error for error in errors):
            passed.append("Paket entspricht dem getesteten Build bis auf die Google-TV-Zugangsdaten")

    if has_id and has_secret and not errors:
        passed.insert(0, "Google TV OAuth: configured")
    return errors, passed


HASHED_ASSET = re.compile(r"^(?P<stem>.+)-[A-Za-z0-9_-]{8}(?P<ext>\.[A-Za-z0-9]+)$")


def compare_with_reference(rel: str, files: list[tuple[str, bytes]], reference: Path,
                           client_id: str, secret: str, notes: list[str]) -> list[str]:
    """Ist das Paket derselbe Stand wie der ohne Zugangsdaten getestete Build?

    Der Fernbedienungslauf prüft ausdrücklich den Zustand „kein Google-Zugang
    im Build" und läuft deshalb gegen einen Build mit leeren TV-Variablen. Hier
    wird belegt, dass sich das ausgelieferte Paket davon nur an den beiden
    Zugangsdaten unterscheidet — und an keiner anderen Stelle.

    Vite hängt an Bündel einen Inhalts-Hash (`index-<hash>.js`). Andere
    Zugangsdaten ergeben einen anderen Hash; verglichen wird deshalb nach dem
    Namen ohne Hash, und Verweise auf gehashte Dateien werden vorher auf diesen
    Namen zurückgeführt.
    """
    errors: list[str] = []
    if not reference.is_dir():
        return [f"{rel}: Referenz-Build {reference} fehlt"]

    package_files: dict[str, bytes] = {}
    marker = "/usr/palm/applications/"
    for name, data in files:
        normalized = "/" + name.lstrip("./")
        if marker in normalized:
            inner = normalized.split(marker, 1)[1].split("/", 1)
            if len(inner) == 2:
                package_files[inner[1]] = data
    reference_files = {
        path.relative_to(reference).as_posix(): path.read_bytes()
        for path in reference.rglob("*") if path.is_file()
    }

    def unhashed(name: str) -> str:
        head, _, base = name.rpartition("/")
        match = HASHED_ASSET.match(base)
        plain = f"{match.group('stem')}{match.group('ext')}" if match else base
        return f"{head}/{plain}" if head else plain

    def by_plain_name(entries: dict[str, bytes]) -> tuple[dict[str, bytes], dict[bytes, bytes]]:
        plain: dict[str, bytes] = {}
        renames: dict[bytes, bytes] = {}
        for name, data in entries.items():
            key = unhashed(name)
            if key in plain:
                errors.append(f"{rel}: Referenz-Vergleich — zwei Dateien ergeben {key}")
            plain[key] = data
            if key != name:
                renames[name.rpartition("/")[2].encode()] = key.rpartition("/")[2].encode()
        return plain, renames

    mine, my_renames = by_plain_name(package_files)
    theirs, their_renames = by_plain_name(reference_files)
    only_package = sorted(set(mine) - set(theirs))
    only_reference = sorted(set(theirs) - set(mine))
    if only_package:
        errors.append(f"{rel}: Referenz-Vergleich — nur im Paket: {', '.join(only_package[:5])}")
    if only_reference:
        errors.append(f"{rel}: Referenz-Vergleich — fehlt im Paket: {', '.join(only_reference[:5])}")

    quoted_id = json.dumps(client_id).encode()
    quoted_secret = json.dumps(secret).encode()
    for key in sorted(set(mine) & set(theirs)):
        ours, reference_bytes = mine[key], theirs[key]
        if ours == reference_bytes:
            continue
        ours = ours.replace(quoted_id, b'""').replace(quoted_secret, b'""')
        for old, new in my_renames.items():
            ours = ours.replace(old, new)
        for old, new in their_renames.items():
            reference_bytes = reference_bytes.replace(old, new)
        if ours == reference_bytes:
            continue
        report: list[str] = []
        renames = only_minifier_renames(ours, reference_bytes, report)
        if renames is None:
            # Der Bericht steht **hinter** der Fundstelle, nicht statt ihrer:
            # Er zählt alle Abweichungen auf, nicht nur die erste, und sagt zu
            # jeder, warum sie nicht als Umbenennung durchgeht. Ohne ihn bleibt
            # nur Raten, und das hat hier schon Läufe gekostet.
            errors.append(
                f"{rel}: Referenz-Vergleich — {key} unterscheidet sich über die "
                f"Zugangsdaten hinaus{where_they_differ(ours, reference_bytes)}"
                + ("".join(f"\n    {line}" for line in report) if report else "")
            )
        else:
            shown = ", ".join(f"{a.decode()}→{b.decode()}" for a, b in sorted(renames.items())[:5])
            notes.append(f"{key}: gleicher Code, andere Namensvergabe des Minifizierers "
                         f"({len(renames)} Name(n): {shown})")
    return errors


MINIFIED_NAME = re.compile(rb"[A-Za-z_$][A-Za-z0-9_$]*")

# Wie lang ein Name höchstens sein darf, um als Vergabe des Minifizierers
# durchzugehen. esbuild zählt `a`, `b`, … `aa`, `ab`, … hoch; bei der Größe
# dieses Bündels endet das im zweistelligen Bereich. Vier ist großzügig
# gerechnet und immer noch weit von allem entfernt, was ein Schlüssel wäre.
MAX_MINIFIED_NAME = 4


IDENTIFIER_BYTE = re.compile(rb"[A-Za-z0-9_$]")


def full_token(data: bytes, start: int, end: int) -> tuple[int, int]:
    """Den Bereich nach beiden Seiten bis an die Grenzen des Bezeichners."""
    while start > 0 and IDENTIFIER_BYTE.match(data, start - 1):
        start -= 1
    while end < len(data) and IDENTIFIER_BYTE.match(data, end):
        end += 1
    return start, end


def only_minifier_renames(ours: bytes, reference: bytes,
                          report: list[str] | None = None) -> dict[bytes, bytes] | None:
    """Unterscheiden sich die beiden nur darin, wie der Minifizierer benennt?

    Der Lauf baut zweimal aus demselben Quelltext — einmal mit leeren
    Zugangsdaten für den Fernbedienungslauf, einmal produktiv. Danach sollen
    beide Bündel gleich sein. In der Praxis sind sie es fast: Am 17.09.2026
    unterschieden sie sich an genau einer Stelle, und zwar so:

        ab Byte 7763 von 424767 (Paket 424767 Bytes)
        Vergleichsbau: …,By=Object.prototype.hasOwnProperty,Wy=Oy.__SECRET_…
        Paket:         …,By=Object.prototype.…,           Ky=Oy.….……

    Gleiche Länge, gleiche Stelle, ein Bezeichner anders: `Wy` gegen `Ky`.
    Derselbe Quelltext baut auf einem anderen Rechner byte-gleich — nachgebaut
    mit realistisch langen erfundenen Werten, mit und ohne
    `npm i playwright --no-save` dazwischen. Der Unterschied entsteht erst auf
    dem Runner und ist eine Namensvergabe, kein Code.

    Byte-Gleichheit ist damit strenger als das, was hier zu belegen ist: dass
    im Paket derselbe Code steckt wie im getesteten Build, plus genau die
    Zugangsdaten. Diese Funktion lässt deshalb Umbenennungen durch — aber nur
    unter Bedingungen, die zusammen keinen eingeschleusten Wert durchlassen:

    * Beide Dateien sind **gleich lang**. Ein eingefügter Wert verschiebt
      alles dahinter; dann gibt es hier keine Nachsicht.
    * Jede abweichende Stelle ist auf beiden Seiten ein vollständiger
      Bezeichner von höchstens vier Zeichen. Eine Client-ID hat 72, ein Secret
      35.
    * Kein abweichender Bezeichner grenzt an ein Anführungszeichen oder steht
      hinter einem Punkt. Eine geänderte Zeichenkette und ein geänderter
      Eigenschaftsname fallen damit weiterhin auf; esbuild benennt
      Eigenschaften ohnehin nicht um.
    * Die Zuordnung ist unter den abweichenden Namen **eindeutig in beide
      Richtungen**: Derselbe Name im Vergleichsbau steht überall für denselben
      im Paket, und keine zwei fallen zusammen. Eine Vertauschung geht damit
      durch, ein Flickenteppich nicht.

    Was sie **nicht** belegt, damit es niemand für mehr hält: Sie prüft die
    Namen nicht gegen den ganzen Rest der Datei. Das wäre erst mit einer
    Geltungsbereichs-Analyse richtig — ein Minifizierer vergibt denselben
    Kurznamen in getrennten Bereichen mehrfach, eine Eindeutigkeit über die
    ganze Datei gibt es also gar nicht, und eine solche Forderung würde jedes
    echte Bündel abweisen. Belegt ist: gleiche Länge, und jede Abweichung ist
    ein kurzer Bezeichner mit einer in sich stimmigen Zuordnung. Für einen
    eingeschleusten Wert reicht das nicht — der ist länger als vier Zeichen
    und verschiebt die Länge. Dass keine fremden Zugangsdaten im Paket liegen,
    belegen ohnehin die Prüfungen davor, nicht diese.

    Gibt die Zuordnung zurück, wenn all das zutrifft, sonst `None`.
    """
    if len(ours) != len(reference):
        if report is not None:
            report.append(f"verschiedene Längen: Paket {len(ours)}, Vergleichsbau {len(reference)}")
        return None

    def token_at(data: bytes, position: int) -> tuple[int, int] | None:
        """Der ganze Bezeichner, in dem `position` liegt."""
        for candidate in MINIFIED_NAME.finditer(data, max(0, position - MAX_MINIFIED_NAME),
                                                position + MAX_MINIFIED_NAME + 1):
            if candidate.start() <= position < candidate.end():
                return candidate.start(), candidate.end()
        return None

    # Erst alle abweichenden Stellen sammeln, dann urteilen. Beim ersten
    # Verstoß auszusteigen wäre schneller, würde aber genau das verschweigen,
    # was man zum Verstehen braucht: wie viele es sind und wie sie aussehen.
    spots: list[tuple[int, int, str | None]] = []
    index = 0
    size = len(reference)
    while index < size:
        if ours[index] == reference[index]:
            index += 1
            continue
        span = token_at(reference, index)
        if span is None or span != token_at(ours, index):
            spots.append((index, index + 1, "kein Bezeichner auf beiden Seiten"))
            index += 1
            continue
        start, end = span
        reason = None
        dotted = False
        if end - start > MAX_MINIFIED_NAME:
            reason = f"länger als {MAX_MINIFIED_NAME} Zeichen"
        else:
            # Was unmittelbar daneben steht, entscheidet, wofür der Name steht.
            before = reference[start - 1:start]
            after = reference[end:end + 1]
            if before in (b'"', b"'", b"`", b"\\") or after in (b'"', b"'", b"`"):
                # Der Inhalt einer Zeichenkette. Das ist nie eine Umbenennung.
                reason = "grenzt an ein Anführungszeichen"
            elif before == b".":
                dotted = True
        spots.append([start, end, reason, dotted])
        index = end

    # Zwei Durchgänge, und die Reihenfolge ist der Punkt.
    #
    # Zuerst nur die freistehenden Namen: Sie sind der Beleg, dass der
    # Minifizierer anders benannt hat, und aus ihnen entsteht die Zuordnung.
    mapping: dict[bytes, bytes] = {}
    backwards: dict[bytes, bytes] = {}
    for spot in spots:
        start, end, reason, dotted = spot
        if reason is not None or dotted:
            continue
        theirs, mine = reference[start:end], ours[start:end]
        if mapping.setdefault(theirs, mine) != mine:
            spot[2] = f"{theirs.decode()} steht schon für {mapping[theirs].decode()}"
        elif backwards.setdefault(mine, theirs) != theirs:
            spot[2] = f"{backwards[mine].decode()} und {theirs.decode()} fallen zusammen"

    # Danach die hinter einem Punkt. Ein Eigenschaftsname ist kein Name, den
    # esbuild von sich aus umbenennt — deshalb war er bisher rundheraus
    # verboten. Lauf 35243770094 zeigt, dass das zu grob ist: Dort tauschen
    # `K`- und `W`-Familie durchgängig die Plätze, 374 Stellen, und vier davon
    # stehen hinter einem Punkt (`.Kc` → `.Wc`, `.Wg` → `.Kg`). Wer ein
    # Modul-Namensobjekt bündelt, liest die umbenannte Bindung eben als
    # Eigenschaft.
    #
    # Durchgelassen wird deshalb **nur**, was oben schon an einem
    # freistehenden Bezeichner belegt wurde. Eine Eigenschaft, die sich ohne
    # zugehörige Umbenennung ändert, fällt weiterhin auf — und genau davor
    # sollte die Regel schützen.
    for spot in spots:
        start, end, reason, dotted = spot
        if reason is not None or not dotted:
            continue
        theirs, mine = reference[start:end], ours[start:end]
        if mapping.get(theirs) != mine:
            spot[2] = "hinter einem Punkt, ohne dieselbe Umbenennung an einem Bezeichner"

    bad = [spot for spot in spots if spot[2] is not None]
    if report is not None and bad:
        report.append(f"{len(spots)} abweichende Stelle(n), davon {len(bad)} keine Umbenennung")
        for start, end, reason, _ in bad[:6]:
            # Zum Anzeigen den **ganzen** Namen, nicht das Bruchstück aus dem
            # Suchfenster. Fürs Urteil genügt das Bruchstück — ein Name, der
            # weiter reicht als vier Zeichen, misst darin immer mindestens
            # fünf und fällt damit ohnehin durch. Zum Lesen genügt es nicht:
            # `'gment'` statt `'react.fragment'` schickt den Nächsten auf die
            # falsche Fährte.
            whole = full_token(reference, start, end)
            theirs = reference[whole[0]:whole[1]].decode("utf-8", "replace")
            mine = MASK_LONG_RUNS.sub("…", ours[whole[0]:whole[1]].decode("utf-8", "replace"))
            report.append(f"  Byte {start}: Vergleichsbau {theirs!r}, Paket {mine!r} — {reason}")
        if len(bad) > 6:
            report.append(f"  … und {len(bad) - 6} weitere")
    if bad:
        return None
    if report is not None:
        report.append(f"{len(spots)} Umbenennung(en) an {len(mapping)} Namen")
    return mapping


MASK_LONG_RUNS = re.compile(r"[A-Za-z0-9_]{10,}")


def where_they_differ(ours: bytes, reference: bytes) -> str:
    """Wo genau — ohne je ein Byte aus dem produktiven Paket zu zeigen.

    „Unterscheidet sich" allein ist eine Sackgasse: Wer den Runner nicht vor
    sich hat, kann nur raten, und Raten hat hier schon einmal einen Lauf
    gekostet. Gezeigt wird deshalb die Stelle und ihre Umgebung — aber
    ausschließlich aus dem **Vergleichsbau**. Der entsteht mit leeren
    Zugangsdaten; in ihm steht keine Client-ID und kein Secret, er lässt sich
    also gefahrlos zitieren. Aus dem produktiven Paket kommen nur Zahlen.
    """
    limit = min(len(ours), len(reference))
    at = next((i for i in range(limit) if ours[i] != reference[i]), limit)
    start = max(0, at - 70)

    def window(data: bytes, mask: bool) -> str:
        text = data[start:at + 70].decode("utf-8", "replace").replace("\n", "⏎")
        # Aus dem Paket nur maskiert: Die Zugangsdaten sind oben schon durch
        # `""` ersetzt, aber verlassen darf man sich darauf nicht — genau das
        # aufzudecken ist ja die Aufgabe dieser Prüfung. Alles, was lang genug
        # für einen Schlüssel ist, wird deshalb unkenntlich. Minifizierte
        # Bezeichner sind ein bis drei Zeichen lang und bleiben lesbar; nur auf
        # sie kommt es an.
        return MASK_LONG_RUNS.sub("…", text) if mask else text

    return (
        f" — ab Byte {at} von {len(reference)} (Paket {len(ours)} Bytes)"
        f"; Vergleichsbau: …{window(reference, mask=False)}…"
        f"; Paket: …{window(ours, mask=True)}…"
    )


def check_package(package: Path | None = None) -> None:
    """Das fertige Paket noch einmal von außen ansehen."""
    if package is None:
        packages = sorted(APP.glob("*.ipk"))
        if not packages:
            warnings.append("Kein .ipk vorhanden — `npm run build && npm run webos:package` prüft mehr.")
            return
        package = packages[-1]
    rel = package_rel(package)

    raw = package.read_bytes()
    if not raw.startswith(b"!<arch>\n"):
        problems.append(f"{rel}: kein ar-Archiv")
        return

    members: dict[str, bytes] = {}
    offset = 8
    while offset + 60 <= len(raw):
        header = raw[offset:offset + 60]
        offset += 60
        name = header[0:16].decode("ascii").strip().rstrip("/")
        try:
            size = int(header[48:58].decode("ascii").strip())
        except ValueError:
            problems.append(f"{rel}: unlesbare Größenangabe für {name}")
            return
        members[name] = raw[offset:offset + size]
        offset += size + (size % 2)

    for required in ("debian-binary", "control.tar.gz", "data.tar.gz"):
        if required not in members:
            problems.append(f"{rel}: {required} fehlt im Paket")
    if members.get("debian-binary", b"").strip() != b"2.0":
        problems.append(f"{rel}: debian-binary ist nicht 2.0")

    if "data.tar.gz" not in members:
        return

    import io

    pattern = re.compile("|".join(re.escape(name) for name in FOREIGN_NAMES), re.IGNORECASE)
    with tarfile.open(fileobj=io.BytesIO(members["data.tar.gz"]), mode="r:gz") as archive:
        names = archive.getnames()
        if not any(name.endswith("/index.html") for name in names):
            problems.append(f"{rel}: index.html fehlt im Paket")

        # Die Startdatei, die Symbole und die Paketbeschreibung.
        for asset in REQUIRED_ASSETS:
            if not any(name.endswith("/" + asset) for name in names):
                problems.append(f"{rel}: {asset} fehlt im Paket")
        if not any(name.endswith("/packageinfo.json") for name in names):
            problems.append(f"{rel}: packageinfo.json fehlt im Paket")

        # Die Version im Paket muss die des Pakets sein.
        wanted_version = str(json.loads((APP / "appinfo.json").read_text(encoding="utf-8")).get("version", ""))
        for name in names:
            if not name.endswith("/appinfo.json") and not name.endswith("/packageinfo.json"):
                continue
            handle = archive.extractfile(name)
            if handle is None:
                continue
            try:
                inside = json.loads(handle.read().decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError) as error:
                problems.append(f"{rel}: {name} ist kein gültiges JSON ({error})")
                continue
            if str(inside.get("version", "")) != wanted_version:
                problems.append(
                    f"{rel}: {name} trägt Version {inside.get('version')!r}, "
                    f"erwartet {wanted_version!r}"
                )

        for member in archive.getmembers():
            if pattern.search(member.name):
                problems.append(f"{rel}: Datei mit fremdem Namen im Paket — {member.name}")
            if not member.isfile():
                continue
            if member.name.endswith((".js", ".css", ".html", ".json")):
                handle = archive.extractfile(member)
                if handle is None:
                    continue
                text = handle.read().decode("utf-8", errors="replace")
                for name in FOREIGN_NAMES:
                    if name in text.lower():
                        problems.append(
                            f"{rel}: „{name}“ steht in {member.name.split('/')[-1]}"
                        )


def main() -> int:
    parser = argparse.ArgumentParser(description="Statische Prüfung der webOS-App und des fertigen Pakets.")
    parser.add_argument("--production", action="store_true",
                        help="produktive Google-TV-Zugangsdaten im Paket erzwingen")
    parser.add_argument("--ipk", type=Path, help="dieses Paket prüfen statt des jüngsten in apps/webos/")
    parser.add_argument("--secrets-dir", type=Path, default=SECRETS_DIR)
    parser.add_argument("--webos-json", type=Path, default=None,
                        help="Standard: <secrets-dir>/google-webos-oauth.json")
    parser.add_argument("--reference-dist", type=Path,
                        help="ohne Zugangsdaten gebauter dist/-Ordner zum Vergleich")
    args = parser.parse_args()
    webos_json = args.webos_json or (args.secrets_dir / "google-webos-oauth.json")

    check_foreign_names()
    check_foreign_hosts()
    check_appinfo()
    check_no_secrets()
    check_key_matches_apple()
    check_versions()
    check_relative_paths()
    check_css_compat()
    check_package(args.ipk)

    package = args.ipk
    if package is None:
        found = sorted(APP.glob("*.ipk"))
        package = found[-1] if found else None
    if package is None:
        if args.production:
            problems.append("--production: kein .ipk zum Prüfen")
    else:
        errors, passed = check_package_credentials(
            package, args.production, args.secrets_dir.expanduser(), webos_json.expanduser(), args.reference_dist,
        )
        problems.extend(errors)
        notes.extend(passed)

    for warning in warnings:
        print(f"WARN  {warning}")
    for problem in problems:
        print(f"ERROR {problem}")
    if not problems:
        for note in notes:
            print(note)

    if problems:
        print(f"\n{len(problems)} Fehler.")
        return 1
    version = "?"
    try:
        version = json.loads((APP / "appinfo.json").read_text(encoding="utf-8")).get("version", "?")
    except (OSError, json.JSONDecodeError):
        pass
    print(
        f"OK — webOS-App geprüft ({len(sources())} Dateien), Version {version} überall gleich, "
        "keine fremden Namen, kein Schlüssel außer dem einen erlaubten, appinfo.json gültig."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
