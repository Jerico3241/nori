# Eigenen Mac als GitHub-Runner (optional)

> **Stand Nori 2.7.0:** macOS, Windows und LG webOS sind eingestellt. Was hier
> über Build macOS und Build Windows steht, beschreibt den früheren Stand.

Die Workflows laufen auf **GitHub-hosted Runnern**:

| Job | Runner |
| --- | --- |
| Build iOS, Swift tests, Release-Job `checks`, Build Android core | `macos-26` (Xcode 26) |
| Check Apple sources, Check release pipeline, Release prepare/publish/validate/cleanup | `ubuntu-latest` |

Ein eigener Mac ist nicht nötig. Die Anleitung darunter gilt nur, falls jemand
die Workflows wieder auf `[self-hosted, macOS]` stellt.

---

## Warum der eigene Mac früher da war

Bei einem **privaten** Repository zählt GitHub jede macOS-Minute **zehnfach**
gegen das Monatskontingent (GitHub Free: 2.000 Minuten). Ist es aufgebraucht
und das Ausgabenlimit steht auf 0 $, stoppen *alle* Workflows — auch die auf
Linux. Ein eigener Mac verbraucht davon nichts, muss aber an, wach und online
sein.

---

## 1. Voraussetzungen auf dem Mac

**Xcode 16 oder neuer** aus dem App Store. Nicht nur die Command Line Tools —
`xcodebuild` braucht das vollständige Xcode.

> Das war beim ersten Lauf am 5.9.2026 auch prompt die Ursache: der Runner
> meldete sich sauber an und nahm die Jobs an, aber beide Builds brachen im
> ersten Schritt ab mit
>
> ```
> xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer
> directory '/Library/Developer/CommandLineTools' is a command line tools instance
> ```
>
> Dieselbe Ursache traf auch die Tests, nur mit anderem Gesicht: `swift test`
> übersetzte Paket und Abhängigkeiten anstandslos und brach erst am Testziel
> ab mit `unable to resolve module dependency: 'XCTest'`. XCTest gehört
> ebenfalls zu Xcode.
>
> Seitdem prüft `tools/require-xcode.sh` das vorweg und sagt statt dessen, was
> zu tun ist.

Warum 16: die iOS-App nutzt hinter `#available(iOS 18.0, *)` die
Zoom-Übergänge. `#available` prüft nur zur Laufzeit, übersetzt wird trotzdem
gegen das SDK des Runners. Xcode 15.4 bringt iOS-SDK 17.5 und scheitert mit
„has no member". Die beiden iOS-Workflows prüfen das inzwischen im ersten
Schritt und brechen mit einer klaren Meldung ab.

Nach der Installation einmal:

```bash
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
xcodebuild -version          # muss 16.x oder höher zeigen
xcodebuild -runFirstLaunch   # Zusatzkomponenten nachinstallieren
```

**Bei einer Beta heißt der Pfad anders.** Ein Xcode aus dem Developer-Programm
liegt als `Xcode-beta.app`, und `xcode-select` zeigt nach einer Neuinstallation
trotzdem auf die Command Line Tools — der Befehl aus jeder Anleitung geht dann
ins Leere:

```bash
ls -d /Applications/Xcode*.app          # zeigt, wie es hier heißt
sudo xcode-select -s /Applications/Xcode-beta.app
xcode-select -p                         # Gegenprobe
```

Eine Beta ist unproblematisch: sie ist neuer als die geforderte 16, und die
Apps bauen weiter gegen ihre Deployment-Targets (iOS 17, macOS 14). Das SDK
darf neuer sein als das Ziel — umgekehrt nicht.
`tools/require-xcode.sh` nennt den gefundenen Pfad in seiner Fehlermeldung,
auch den der Beta.

Alles Weitere ist schon da: `git`, `curl`, `zip`, `unzip`, `ruby` und
`python3` kommen mit macOS und den Command Line Tools, die Xcode mitbringt.
Node holen die Läufe selbst (`actions/setup-node`). Homebrew wird nicht
gebraucht — die Workflows kommen bewusst ohne aus, deshalb legt `release.yml`
das GitHub-Release über die REST-API an (`tools/nori-release.py`, nur
Python-Standardbibliothek) und nicht über die `gh`-CLI.

Für Windows braucht der Mac **kein Wine**: `electron-builder` 26 packt
Installer und ZIP unter macOS ohne. Auf einem Mac mit Apple-Chip muss aber
**Rosetta 2** installiert sein — der NSIS-Compiler, den `electron-builder`
mitbringt, liegt für macOS nur als Intel-Programm vor
(`mac/makensis: Mach-O 64-bit executable x86_64`). `Build Windows` prüft das
vor dem Packen; nachinstallieren mit
`softwareupdate --install-rosetta --agree-to-license`.

Gegenprobe:

```bash
git --version && python3 --version && swift --version
```

## 2. Registrierungstoken holen

Im Browser:

**github.com/jerico3241/nori → Settings → Actions → Runners → New self-hosted
runner**, dort **macOS** und die passende Architektur wählen (**arm64** bei
Apple Silicon, **x64** bei Intel).

Die Seite zeigt danach fertige Befehle mit der aktuellen Runner-Version und
einem Token. **Das Token ist rund eine Stunde gültig** — läuft es ab, einfach
dieselbe Seite neu laden, es steht dann ein neues da.

Diese Seite ist der einzige Schritt, den ich nicht übernehmen kann: das Token
erscheint nur dort, in deinem angemeldeten Browser.

## 3. Herunterladen und auspacken

Die Befehle von der GitHub-Seite kopieren — sie sehen so aus, `<VERSION>` steht
dort als echte Nummer:

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-osx-arm64-<VERSION>.tar.gz -L \
  https://github.com/actions/runner/releases/download/v<VERSION>/actions-runner-osx-arm64-<VERSION>.tar.gz
tar xzf ./actions-runner-osx-arm64-<VERSION>.tar.gz
```

Bei einem Intel-Mac heißt das Paket `osx-x64` statt `osx-arm64`.

## 4. Anmelden

```bash
cd ~/actions-runner
./config.sh --url https://github.com/jerico3241/nori --token <TOKEN>
```

Vier Rückfragen, alle mit Enter zu bestätigen:

| Frage | Antwort |
| --- | --- |
| `Enter the name of the runner group` | Enter (Default) |
| `Enter the name of this runner` | Enter (Rechnername) |
| `Enter any additional labels` | Enter — **nichts eintragen** |
| `Enter name of work folder` | Enter (`_work`) |

Bei den Bezeichnungen wirklich nichts eintippen: `self-hosted`, `macOS` und
`ARM64` vergibt der Runner von selbst, und `self-hosted` + `macOS` sind genau
die beiden, auf die die Workflows warten. Eigene Bezeichnungen schaden nicht,
ersetzen diese aber nicht.

Zum Ausprobieren reicht jetzt:

```bash
./run.sh
```

Das läuft im Vordergrund, bis man Strg-C drückt — gut für den ersten Test,
nichts für den Dauerbetrieb.

## 5. Als Dienst einrichten

Damit der Runner nach einem Neustart von selbst wiederkommt:

```bash
cd ~/actions-runner
./svc.sh install
./svc.sh start
./svc.sh status
```

`svc.sh install` legt einen LaunchAgent an. Das heißt: **der Runner läuft nur,
solange dein Benutzer angemeldet ist.** Nach einem Neustart also einmal
einloggen; ein gesperrter Bildschirm ist in Ordnung, ein Abmelden nicht.

Ohne `sudo` ausführen — `svc.sh` ruft `sudo` selbst auf, wo es nötig ist.

## 6. Schlafen verhindern

Ein schlafender Mac nimmt keine Jobs an; sie warten dann still bis zum
Aufwachen. Systemeinstellungen → Batterie bzw. Energie sparen:

- **„Automatischen Ruhezustand … deaktivieren"** einschalten (Netzbetrieb)
- am Laptop hilft nur der geöffnete Deckel oder ein externer Bildschirm

Auf der Kommandozeile, dauerhaft für den Netzbetrieb:

```bash
sudo pmset -c sleep 0 disablesleep 1
pmset -g                     # Gegenprobe
```

Nur für eine einzelne Sitzung genügt `caffeinate -dimsu`.

## 7. Prüfen, dass es läuft

Auf **Settings → Actions → Runners** muss der Eintrag jetzt grün als **Idle**
stehen. Wenn ja, den ersten Lauf auslösen:

**Actions → Build macOS → Run workflow**

Der Lauf sollte innerhalb weniger Sekunden von „Queued" auf „In progress"
springen und nach rund einer Minute grün sein.

| Symptom | Ursache |
| --- | --- |
| Bleibt in „Queued" | Bezeichnungen passen nicht (auf der Runner-Seite nachsehen, ob dort `self-hosted` und `macOS` stehen), Mac schläft, oder ein anderer Job läuft noch — es gibt nur einen Runner |
| Bricht in „Toolchain prüfen" ab | Xcode fehlt, ist zu alt oder nicht ausgewählt. Die Meldung nennt den passenden Befehl; Schritt 1 dieser Anleitung |
| Bricht in „Set up job" ab | Der Runner-Dienst läuft nicht mehr — `./svc.sh status` |

## 8. Betrieb

```bash
cd ~/actions-runner
./svc.sh status     # läuft er?
./svc.sh stop       # anhalten
./svc.sh start      # weiter
tail -f _diag/Runner_*.log
```

Der Arbeitsordner `~/actions-runner/_work` wächst mit der Zeit. Der Runner
räumt ihn nicht selbst auf; er lässt sich bei angehaltenem Dienst gefahrlos
löschen, der nächste Job checkt neu aus.

Läuft ein Job schief, laden die Workflows ihr Build-Log als Artefakt hoch —
das ist derselbe Weg wie bei den GitHub-Runnern, daran ändert sich nichts.

## 9. Wieder abmelden

```bash
cd ~/actions-runner
./svc.sh stop
./svc.sh uninstall
./config.sh remove --token <NEUES TOKEN VON DER RUNNER-SEITE>
```

Danach die Workflows wieder auf die GitHub-hosted Labels stellen
(`macos-26`, `ubuntu-latest`, `windows-latest`), sonst warten sie auf einen
Runner, den es nicht mehr gibt.

---

## Sicherheitshinweis

Ein self-hosted Runner führt aus, was in den Workflows dieses Repositories
steht — auf deinem Mac, mit deinen Benutzerrechten. Bei einem privaten
Repository mit bekannten Mitwirkenden ist das der übliche Fall. Sollte das
Repository je öffentlich werden, **vorher** den Runner abmelden: dann könnte
jeder über einen Pull Request Code darauf ausführen. GitHub rät aus genau
diesem Grund von self-hosted Runnern an öffentlichen Repositories ab.

Eingehende Ports sind nicht nötig; der Runner baut die Verbindung selbst über
HTTPS nach außen auf.
