#!/usr/bin/env python3
"""Statische Prüfung der webOS-App von Nori.

Zwei Fragen, die sich nicht durch Hinsehen beantworten lassen:

1. Steckt in Quelltext oder Paket etwas von der Referenz-App? Weder Name noch
   Marke noch ein Aufruf ihres Dienstes darf in Nori landen. Die Referenz durfte
   für Bedienkonzepte angesehen werden, für nichts sonst.
2. Ist `appinfo.json` gültig? webOS lehnt ein Paket mit einem unbekannten Feld
   nicht ab — es ignoriert es. Ein Tippfehler fällt sonst erst auf dem Fernseher
   auf, und auch dort nur als „tut nichts".

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
    check_package()

    for warning in warnings:
        print(f"WARN  {warning}")
    for problem in problems:
        print(f"ERROR {problem}")

    if problems:
        print(f"\n{len(problems)} Fehler.")
        return 1
    print(f"OK — webOS-App geprüft ({len(sources())} Dateien), keine fremden Namen, appinfo.json gültig.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
