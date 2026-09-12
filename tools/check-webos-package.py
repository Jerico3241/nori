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

    python3 tools/check-webos-package.py

Exit-Code 1 bei ERROR, 0 sonst. Ergänzt `tools/check-apple-sources.py`, das
dieselbe Aufgabe für die beiden Apple-Targets übernimmt.
"""

from __future__ import annotations

import json
import re
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps/webos"
CORE = ROOT / "shared/nori-core"
API = ROOT / "services/nori-api"

# Symbole, die im Paket liegen müssen. Ein Paket ohne sie installiert sich und
# erscheint auf dem Fernseher als weiße Fläche im Launcher.
REQUIRED_ASSETS = ["icon-80.png", "icon-130.png", "splash-1920x1080.png"]

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

problems: list[str] = []
warnings: list[str] = []


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


def check_package() -> None:
    """Das fertige Paket noch einmal von außen ansehen."""
    packages = sorted(APP.glob("*.ipk"))
    if not packages:
        warnings.append("Kein .ipk vorhanden — `npm run build && npm run webos:package` prüft mehr.")
        return
    package = packages[-1]
    rel = package.relative_to(ROOT)

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
    check_foreign_names()
    check_foreign_hosts()
    check_appinfo()
    check_no_secrets()
    check_key_matches_apple()
    check_versions()
    check_relative_paths()
    check_package()

    for warning in warnings:
        print(f"WARN  {warning}")
    for problem in problems:
        print(f"ERROR {problem}")

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
