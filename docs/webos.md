# Nori für LG webOS

Die TV-Fassung von Nori. Eigenständige App, kein skalierter Webauftritt:
vollständig mit der Fernbedienung bedienbar, auf 1920 × 1080 ausgelegt und auf
andere Auflösungen mitskalierend.

## Aufbau

```
apps/webos/          TV-Oberfläche (React, TypeScript, Enact Spotlight, hls.js)
shared/nori-core/    gemeinsamer Kern in TypeScript — Modelle, Provider,
                     Parser, Hoster-Resolver, Bibliotheksregeln
services/nori-api/   Provider-Schicht als HTTP-Dienst, benutzt denselben Kern
```

Der Kern ist die TypeScript-Entsprechung von `native/NoriCore/`, dem
gemeinsamen Swift-Kern der Apple-Apps. Maßgeblich ist für beide
`config/contract.json`. Feldnamen, Regeln und Ablageformat sind übernommen,
nicht neu erfunden: eine `library.json` aus der iOS- oder macOS-App liest sich
hier ohne Umschreiben.

### Warum es den Nori-Server gibt

iOS und macOS rufen AniWorld und Serienstream direkt ab und setzen dabei
Kopfzeilen, die ein Browser nicht setzen darf — vor allem `Referer`, ohne den
viele Hoster den Stream verweigern. Auf dem Fernseher läuft Nori aber in einem
Browser.

```
webOS-Client
     ↓  HTTP
services/nori-api
     ↓  shared/nori-core
AniWorld / Serienstream
     ↓
HosterResolver
     ↓
Weiterreichung mit Referer  (HLS-Playlists werden umgeschrieben,
     ↓                       damit auch die Segmente darüber laufen)
Hoster
```

Der Client kennt keinen einzigen Hoster: er bekommt ein `PlaySource` und eine
Adresse, die er laden kann. Hosterspezifische Extraktion liegt an genau einer
Stelle, im Kern.

**Direkter Weg.** In den Einstellungen lässt sich statt des Servers „Direkt vom
Fernseher" wählen. Dann benutzt der Client denselben Kern selbst. Das kommt
ohne Einrichtung aus, hängt aber davon ab, dass webOS der App fremde Abrufe
erlaubt und der Hoster ohne `Referer` ausliefert — ein Rückfall, kein Ersatz.

## Voraussetzungen

- Node 20 oder neuer
- Für Installation und Protokolle: das LG-SDK, `npm i -g @webosose/ares-cli`
- Ein LG-Fernseher mit webOS 6 oder neuer im Entwicklermodus

Das Paket entsteht **ohne** SDK: `npm run webos:package` schnürt das `.ipk`
selbst (ar plus tar, siehe `apps/webos/tools/package-ipk.mjs`).

## Bauen

```bash
cd apps/webos
npm install
npm run build          # prüft Typen und baut nach dist/
npm run webos:package  # ergibt tv.nori.app_1.0.0_all.ipk
```

Vom Repository-Stamm aus geht auch `npm run webos:build` und
`npm run webos:package`.

Der Nori-Server daneben:

```bash
cd services/nori-api
npm install
npm run dev            # hört auf 0.0.0.0:8730
```

## Entwicklungsstand

```bash
cd services/nori-api && npm run dev &
cd apps/webos && npm run dev
```

Vite liegt auf `http://localhost:8731` und reicht `/api` an den Server weiter.
Im Browser lässt sich alles mit den Pfeiltasten und Enter bedienen; Escape
entspricht der Zurück-Taste der Fernbedienung.

## Installation auf dem Fernseher

1. **LG-Konto anlegen** auf <https://lgaccount.lge.com> und am Fernseher
   anmelden.
2. **Developer Mode installieren**: im LG Content Store nach „Developer Mode"
   suchen, installieren, starten, mit demselben Konto anmelden und
   *Dev Mode Status* auf **on** stellen. Der Fernseher startet neu und zeigt
   danach eine **Passphrase** und seine **IP-Adresse**.
3. **Gerät eintragen** (einmalig, am Rechner):

   ```bash
   ares-setup-device --add tv --info "{'host':'192.168.1.50','port':'9922','username':'prisoner'}"
   ares-novacom --device tv --getkey        # fragt nach der Passphrase
   ```

4. **Installieren und starten**:

   ```bash
   cd apps/webos
   npm run webos:install tv
   npm run webos:launch tv
   ```

   Ohne Gerätenamen wird das voreingestellte Gerät benutzt; alternativ
   `NORI_WEBOS_DEVICE=tv` setzen.

5. **Nori einrichten**: beim ersten Start unter *Einstellungen → Verbindung*
   die Adresse des Nori-Servers eintragen, etwa `http://192.168.1.20:8730`, und
   auf **Prüfen** gehen. Fernseher und Server müssen im selben Netz sein.

### Fehlersuche

```bash
npm run webos:inspect tv    # Web-Inspector im Browser öffnen
node tools/webos-cli.mjs log tv
```

Im Protokoll trägt alles von Nori das Präfix `[Nori:webOS]`. Ausführlich wird
es erst, wenn in den Einstellungen *Diagnoseprotokoll* eingeschaltet ist —
sonst bleiben nur Warnungen und Fehler übrig.

### Entwicklermodus verlängern

Die Developer-Mode-App zeigt eine Restlaufzeit (üblicherweise 50 Stunden). Der
Knopf **Extend Dev Mode Status** in derselben App setzt sie zurück; das geht
beliebig oft, muss aber vor Ablauf geschehen, sonst wird die App vom Fernseher
entfernt und muss neu installiert werden.

## Bedienung

| Taste | Wirkung |
| --- | --- |
| Pfeiltasten | Fokus bewegen; im Player ohne sichtbare Bedienung Links/Rechts = spulen, Hoch = Drawer |
| OK (13) | auslösen; im Player ohne Bedienung Wiedergabe/Pause |
| Zurück (461 / 10009) | Drawer zu → Bedienung zu → Player verlassen → Ansicht zurück → App verlassen |
| Play (415) / Pause (19) / Stop (413) | Wiedergabe steuern |
| Vor-/Zurückspulen (417 / 412) | springen, bei gehaltener Taste schneller |

Am Rechner ersetzen Escape die Zurück-Taste und die Leertaste Wiedergabe/Pause.

## Unterstützte Stände

Gebaut wird auf **Chrome 79** — die Engine von webOS 6. Damit läuft dieselbe
Datei auf webOS 6 bis 26; neuere Sprachmerkmale werden übersetzt, `?.` und `??`
eingeschlossen.

Was **nicht** geprüft ist: die Wiedergabe auf einem echten Gerät. Ob webOS eine
bestimmte Playlist nativ abspielt oder hls.js übernehmen muss, entscheidet sich
erst dort — der Player fragt zur Laufzeit `canPlayType` und wählt danach.

## Prüfen

```bash
npm --prefix shared/nori-core test     # Kern gegen dieselben Fixtures wie Swift
python3 tools/check-webos-package.py   # Quelltext und .ipk, appinfo.json
cd apps/webos && npm run typecheck
```

In der CI macht das der Lauf **Build webOS**, ausgelöst durch Pushes auf
`apps/webos/**`, `shared/nori-core/**` und `services/nori-api/**`. Er läuft auf
demselben self-hosted Mac wie alle anderen Läufe (siehe
`docs/self-hosted-runner.md`) — ist der aus, wartet der Job in der
Warteschlange, statt zu scheitern. Xcode braucht er nicht, nur Node.

Die Oberfläche lässt sich mit einer nachgebauten Fernbedienung durchspielen:

```bash
cd apps/webos
npm run build
npm run mock &                          # Nori-Server mit festen Daten
npm i -D playwright && npx playwright install chromium
npm run test:tv
```

Der Lauf drückt echte LG-Tastencodes und prüft unter anderem, dass nie ein
Zustand ohne Fokus entsteht, dass der Fokus beim Zurückgehen auf derselben
Kachel steht, dass der Drawer den Fokus einsperrt und dass nach dem Verlassen
des Players kein Stream weiterläuft.

## Bekannte Einschränkungen

- Kein Abgleich zwischen Geräten: die Bibliothek liegt im `localStorage` des
  Fernsehers. Das Format ist dasselbe wie in `library.json`, ein Abgleich ist
  also vorbereitet, aber nicht gebaut (siehe `docs/synchronisation.md`).
- Intro-, Recap- und Ending-Sprungmarken fehlen, weil Nori dafür keine Daten
  hat. Erfundene Zeitmarken wären schlechter als keine.
- Untertitelspuren werden nicht getrennt angeboten; „GerSub" ist bei beiden
  Quellen eine eigene Tonspur, keine Textspur.
- TMDB-Bilder nur mit eigenem Schlüssel. Ohne ihn zeigt Nori die Cover der
  Quellen — ein gültiger Zustand.
