# Nori für Windows

Die Desktop-App unter `apps/windows/`. Sie benutzt denselben Kern und dieselbe
Anwendungsschicht wie der Fernseher und hat eine eigene Oberfläche für Maus,
Tastatur, Trackpad und ein Fenster, dessen Größe sich ändert.

## Was sie ersetzt

Bis Version 1.8.0 bestand „Nori für Windows" aus zwei Teilen: `desktop/`, einer
Electron-Hülle, und `server/`, einem gebauten Nitro-Bundle. Die Hülle startete
den Server als eigenen Prozess und zeigte in einem Fenster
`http://127.0.0.1:17321`.

Das hieß im Alltag: ein zweiter Node-Prozess, ein belegter Port, eine
Wartezeit beim Start und ein Fehlerbild („Server antwortet nicht"). Und im
Repository hieß es: der Quelltext der Web-App lag gar nicht darin — nur
minifizierte `.mjs`-Dateien mit Hash-Namen. Was man nicht lesen kann, kann man
nicht ändern.

`apps/windows/` ist der Ersatz und besteht aus Quelltext. Mit Windows 2.0.0
sind `desktop/` und `server/` entfallen.

## Aufbau

```
apps/windows/
├── src/main/        Hauptprozess: Fenster, Quellenschicht, Google, Streams
│   ├── main.ts          Fenster, IPC, `Referer` für Streams
│   ├── gateway.ts       die Quellenschicht — direkt oder über einen Server
│   ├── google.ts        OAuth mit PKCE über den Systembrowser
│   ├── preload.ts       die Brücke: eine feste Liste von Kanälen
│   └── windowState.ts   Größe und Vollbildzustand merken
├── src/renderer/    Oberfläche: Seiten, Player, Zustand, Stylesheets
├── test/            Desktop-Prüfung über Playwright (`_electron`)
├── tools/           esbuild-Lauf für den Hauptprozess
└── build/           Symbole für Fenster und Installer
```

Darunter liegen zwei geteilte Schichten:

```
shared/nori-app/     Zustand, Dienste, Hooks, Wiedergabe, `Artwork`, `Icon`
shared/nori-core/    Modelle, Provider, Parser, Hoster-Resolver, TMDB
```

`shared/nori-app/` teilt sich der Schreibtisch mit dem Fernseher. Sie enthält
keine Annahme über das Gerät: was sie darüber wissen muss, fragt sie über
`NoriPlatform`, und `src/renderer/platform.ts` meldet die Antworten dieses
Rechners beim Start an. **Wer dort etwas ändert, ändert beide Apps.**

## Warum die Quellen im Hauptprozess laufen

Ein Fenster kann AniWorld und Serienstream nicht selbst lesen. Drei Gründe,
und keiner davon ist zu umgehen:

1. **Herkunftsprüfung.** Ein Abruf von `file://` auf `aniworld.to` ist ein
   fremder Ursprung; die Quellen setzen keine CORS-Kopfzeilen.
2. **`Referer`.** Viele Hoster liefern ohne diese Kopfzeile nichts aus. Ein
   Browser lässt sie nicht setzen — das ist der Sinn der Sperrliste für
   verbotene Kopfzeilen.
3. **Weiterleitungen.** Der Resolver muss das Ziel einer Weiterleitung lesen,
   bevor er ihr folgt. `fetch` im Browser gibt das nicht her.

Der Fernseher löst das mit einem Nori-Server nebenan. Auf dem Schreibtisch
braucht es den nicht: Der Hauptprozess **ist** Node, und dieselbe
`DirectGateway` aus `@nori/core`, die auch `services/nori-api` benutzt, läuft
direkt darin — mit `linkedom` als Parser, weil Node keinen `DOMParser` hat.

```
Fenster
   ↓  IPC (feste Liste aus preload.ts)
Hauptprozess
   ↓  shared/nori-core  (DirectGateway)
AniWorld / Serienstream
   ↓
HosterResolver
   ↓
Adresse des Hosters  →  zurück ins Fenster
```

Das Fenster lädt Bild und Ton dann **direkt** beim Hoster. Den `Referer`
setzt der Hauptprozess für genau diese Adressen
(`session.webRequest.onBeforeSendHeaders`) — ein `<video src>` kann das nicht.
Kein Proxy, kein Zwischenspeichern, kein zweiter Weg durch den Quelltext.

### Der Weg über einen Nori-Server

Wer schon einen betreibt — für den Fernseher zum Beispiel —, kann den
Schreibtisch daran hängen: ein Zwischenspeicher für alle Geräte, eine
Ratenbegrenzung statt mehrerer. Einstellungen → *Quelle der Daten* → *Über
einen Nori-Server*.

Auch dieser Weg läuft im Hauptprozess, und er liefert **nur Auskunft**: Listen,
Details, aufgelöste Adressen. Bild und Ton holt Nori weiterhin selbst. Der
Umweg über den Server wäre `http:`, und die Inhaltsrichtlinie des Fensters
lässt das zu Recht nicht zu — was im Fenster läuft, soll nicht ins lokale Netz
telefonieren können. Gebraucht wird der Umweg hier ohnehin nicht: den
`Referer`, für den es ihn auf dem Fernseher gibt, setzt hier der
Hauptprozess.

TMDB nimmt denselben Kanal (`nori:http`). Der Hauptprozess lässt dort genau
zwei Ziele zu: TMDB und den eingetragenen Nori-Server.

## Sicherheit

| | |
| --- | --- |
| `contextIsolation` | an |
| `sandbox` | an |
| `nodeIntegration` | aus |
| `remote` | nicht vorhanden |
| Inhaltsrichtlinie | `script-src 'self'`, `object-src 'none'`, `base-uri 'none'`, `frame-src 'none'` |
| fremde Adressen | Systembrowser (`setWindowOpenHandler`, `will-navigate`) |
| Tokens | `safeStorage`, `%APPDATA%\Nori\google-tokens.bin`, Rechte 0600 |

Das Fenster sieht ausschließlich, was `src/main/preload.ts` über
`contextBridge` freigibt — eine feste Liste von Kanälen, keine offene Brücke.
Ein eingeschleustes Skript aus einer Hoster-Seite käme darüber nicht an das
Dateisystem; ausgeführt würde es wegen `script-src 'self'` ohnehin nicht.

**Das Refresh-Token verlässt den Hauptprozess nie.** Das Fenster bekommt ein
Zugriffstoken, das eine Stunde gilt, und holt sich bei Bedarf ein neues.
Weder Tokens noch Autorisierungscodes noch das Client-Secret gehen ins
Protokoll.

## Google-Anmeldung

Ein Knopf: *Mit Google anmelden*. Dahinter steht Authorization Code mit PKCE
und einer Rückgabeadresse auf `127.0.0.1` mit zufälligem Port (RFC 8252) —
der Systembrowser des Nutzers, keine eingebettete Anmeldeseite, kein eigener
Auth-Server, kein Proxy.

Angefordert werden `drive.appdata` und `drive.file`:

- **`drive.appdata`** ist die primäre Ablage, wie auf iPhone, iPad und Mac.
  Ein versteckter Ordner, den nur Nori sieht.
- **`drive.file`** ist der sichtbare Spiegel im Ordner „Nori", und er wird nur
  geschrieben, wenn *Mit Fernseher teilen* eingeschaltet ist. Der Fernseher
  kommt an `drive.appdata` nicht heran — warum, steht in
  [google-drive-sync.md](google-drive-sync.md), Abschnitt 10.

Client-ID und Client-Secret kommen aus der Umgebung und werden beim Bauen fest
eingesetzt:

```bash
export NORI_GOOGLE_DESKTOP_CLIENT_ID=...
export NORI_GOOGLE_DESKTOP_CLIENT_SECRET=...
npm --prefix apps/windows run build
```

Eingecheckt wird keines. Ohne sie entsteht ein Paket ohne Abgleich, und die
Oberfläche sagt das in einem Satz, statt ein Eingabefeld anzubieten.

## Bedienung

| Taste | Wirkung |
| --- | --- |
| `Alt` + `←` / `→` | zurück / vorwärts |
| `Ctrl` + `F` | ins Suchfeld |
| `F11` | Vollbild |
| `Escape` | zurück, im Player: Player verlassen |

Im Player:

| Taste | Wirkung |
| --- | --- |
| `Leertaste`, `K` | anhalten / weiter |
| `←` / `→` | springen |
| `↑` / `↓` | Lautstärke |
| `F` | Vollbild |
| `M` | stumm |
| `N` | nächste Folge |

Reihen lassen sich mit dem Rad schieben, mit der Maus ziehen oder über zwei
Knöpfe, die beim Überfahren erscheinen.

## Wo die Daten liegen

| | |
| --- | --- |
| Bibliothek, Einstellungen | `%APPDATA%\Nori` (Electrons `userData`) |
| Google-Tokens | `%APPDATA%\Nori\google-tokens.bin`, verschlüsselt |
| Fenstergröße | `%APPDATA%\Nori\window-state.json` |

Ausdrücklich **nicht** neben der EXE, wie es die vorherige Fassung tat: ein
Installationsordner unter `Program Files` ist für einen normalen Benutzer
nicht beschreibbar, und eine tragbare Fassung auf einem USB-Stick nähme fremde
Bibliotheken mit.

## Bauen

```bash
npm --prefix apps/windows install
npm --prefix apps/windows run build      # tsc --noEmit, esbuild, Vite
npm --prefix apps/windows run package    # Installer und ZIP nach release/
```

Heraus kommen:

| Datei | Was es ist | Name im Release |
| --- | --- | --- |
| `release/Nori-Setup-<version>.exe` | NSIS-Installer, ohne Administratorrechte, mit wählbarem Zielordner | `Nori-Windows-v<version>.exe` |
| `release/Nori-<version>-portable.zip` | zum Entpacken, nichts wird installiert | `Nori-Windows-v<version>.zip` |
| `release/win-unpacked/` | derselbe Inhalt, ungepackt | — |

Die Nummer ist die gemeinsame Nori-Version aus `apps/windows/package.json`;
`python3 tools/nori-version.py` setzt und prüft sie zusammen mit allen anderen
Plattformen.

Der Hauptprozess wird mit esbuild zu **einer** CommonJS-Datei gebündelt
(`dist-main/main.cjs`), samt Kern und `linkedom`. Deshalb liegt kein
`node_modules` im Paket: das sind ein paar hundert Dateien weniger, die beim
Start einzeln von der Platte kommen. CommonJS, weil Electron `preload` nur so
lädt.

### In der CI bauen

`Build Windows` (`.github/workflows/build-windows.yml`) läuft auf dem
**self-hosted Mac**, wie alle anderen Läufe des Projekts.

Vorher lag er auf einem von GitHub gestellten Windows-Runner. Das geht nicht
mehr: Bei einem privaten Repository zählen gestellte Runner gegen das
Minutenkontingent — Windows mit Faktor 2 —, und das Kontingent ist
aufgebraucht. Lauf `35227553568` endete nach vier Sekunden mit
`billable.WINDOWS.total_ms = 0`: Der Job hat nie einen Runner bekommen.

**Was der Mac kann:** bauen, durchspielen und packen. `tsc`, `esbuild` und
Vite sind plattformunabhängig, und die Desktop-Prüfung startet Electron für
macOS mit demselben Haupt- und Renderer-Code, den Windows ausführt. Packen
geht ohne Wine: `electron-builder` 26 schreibt Symbol und Versionsangaben der
EXE mit `resedit` (reines JavaScript) und liest die
NSIS-Deinstallationsroutine unter macOS direkt aus dem Installer
(`UninstallerReader`). Am 17.09. auf dem Runner-Mac nachgestellt — ohne Wine
entstanden `Nori-Setup-2.6.0.exe` (86 MB) und `Nori-2.6.0-portable.zip`
(122 MB), beide mit Produktversion `2.6.0.0`. Wine braucht es nur unter
Linux (siehe unten). Auf einem Mac mit Apple-Chip braucht es dafür
**Rosetta 2**: Der mitgelieferte NSIS-Compiler ist ein Intel-Programm. Der
Schritt *Voraussetzungen fürs Packen* prüft das vorher.

**Was er nicht kann:** das gepackte `Nori.exe` starten. Der Schritt
*Desktop-Prüfung gegen das Paket* steht unter `if: runner.os == 'Windows'`.
Ein auf dem Mac geschnürtes Paket ist damit **kreuzgebaut und auf dem
Zielsystem ungetestet**. Geprüft wird es trotzdem, von außen:
`tools/nori-release.py verify` liest die Produktversion von `Nori.exe` und
Installer, packt `app.asar` aus und vergleicht Version und Inhalt.

**Ein Windows-Runner** lässt sich ohne Änderung am Workflow wählen: die
Repository-Variable `NORI_WINDOWS_RUNNER` auf die Bezeichnungen setzen, etwa
`["self-hosted", "Windows"]`. Er braucht Git Bash, `python3` im `PATH` und
`openssl`; Node holt der Lauf selbst. Dann laufen alle Schritte, und die
Desktop-Prüfung läuft zweimal — gegen den Quellordner und gegen das gepackte
`app.asar`.

**Wann er läuft:**

| Auslöser | Ergebnis |
| --- | --- |
| Push, der Windows, die geteilte Schicht oder den Kern berührt | bauen, prüfen, packen — Installer und ZIP werden **nicht** hochgeladen (zusammen rund 200 MB; das Artefakt-Kontingent war schon einmal voll) |
| von Hand, *Actions → Build Windows → Run workflow* | dasselbe, Installer und ZIP liegen drei Tage am Lauf (`Nori-Windows-v<VERSION>-<commit>`) |
| *Nori Release* | dasselbe mit `release-version`; Installer und ZIP heißen `Nori-Windows-v<VERSION>.exe` und `.zip` und hängen am gemeinsamen Release |

**Kein Tag-Auslöser.** Veröffentlicht wird ausschließlich über *Nori Release*
([releases.md](releases.md)). Ein Tag `windows-v…` entsteht nicht mehr.

Google-Zugangsdaten kommen aus den Repository-Secrets
`NORI_GOOGLE_DESKTOP_CLIENT_ID` und `NORI_GOOGLE_DESKTOP_CLIENT_SECRET`
(*Settings → Secrets and variables → Actions*). Eingetragen wird der
OAuth-Client vom Typ „Desktop-App“, den Nori für Windows benutzen soll.
Fehlen sie, entsteht bei einem Push ein Paket ohne Abgleich — und die
Oberfläche sagt das. **Für einen Release sind sie Pflicht:** *Nori Release*
bricht dann schon im ersten Job ab, und die Paketprüfung verlangt, dass die
Client-ID wirklich im Hauptprozess steckt. Stand 17.09. sind beide Secrets
**nicht** gesetzt; bis dahin lässt sich Windows im Release abwählen.

### Von Linux aus bauen

Geht, braucht aber Wine — `electron-builder` ruft für die Windows-Ressourcen
und die Deinstallationsroutine Windows-Programme auf:

```bash
apt-get install -y wine64 wine32:i386 wine
WINEPREFIX=/root/.wine64 WINEARCH=win64 wine wineboot -u
```

Ohne die **32-Bit**-Hälfte scheitert NSIS mit
`failed to load syswow64\ntdll.dll`. Ein `wine64` allein reicht nicht.

## Prüfen

```bash
npm --prefix apps/windows run build
npm i --no-save playwright              # in apps/windows
xvfb-run -a npm --prefix apps/windows run test:desktop
```

Playwright startet die **gebaute** App über `_electron.launch` — derselbe
Hauptprozess, derselbe Vorlader und dieselbe Oberfläche, die auch im Installer
landen, nur unter Linux statt Windows. Geprüft werden Start, Brücke, Bilder,
Navigation, Suche, Detailseite, Player samt echter Wiedergabe, Fenstergröße,
Vollbild, Überlappungen, Schriftgrößen, Google-Zustand und Fehlerzustände.

Der Nachbau des Nori-Servers läuft dafür über `https:` mit einem
Wegwerf-Zertifikat, das die Prüfung selbst erzeugt (`NORI_MOCK_TLS=1`);
Electron bekommt `--ignore-certificate-errors` mit. Über `http:` wäre der
Nachbau nach der Inhaltsrichtlinie der App gesperrt — und eine Prüfung, die
dafür die Richtlinie lockert, prüft nicht mehr die App, die ausgeliefert wird.
Der Startschalter steht in der Prüfung und in keiner Zeile des Programms.

**Was das nicht ist:** kein Beweis, dass Nori auf Windows läuft. Chromium,
Node und der Kern sind dieselben; der Fensterrahmen, die DPI-Skalierung,
WebView-Codecs und SmartScreen entscheiden sich auf dem Zielsystem.

## Bekannte Einschränkungen

- **Nicht signiert.** Windows SmartScreen meldet sich beim ersten Start:
  *Weitere Informationen → Trotzdem ausführen*. Eine Signatur bräuchte ein
  Zertifikat, das dieses private Projekt nicht hat.
- **Kein automatisches Update.** `electron-builder` kann das; es ist bewusst
  nicht eingeschaltet, weil es einen Ort bräuchte, an dem die Pakete liegen.
- **Nur x64.** Für ARM-Windows wäre ein eigener Lauf nötig.
- Die App wurde in dieser Entwicklungsumgebung unter Linux gebaut und geprüft.
  Auf echter Windows-Hardware ist sie noch nicht gelaufen.
