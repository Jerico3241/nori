# Nori auf Android

Der Plan in einem Satz: **der geteilte Kern bleibt Swift, die Oberfläche wird
Compose.**

## Warum nicht die Web-App verpacken

Naheliegend wäre, die vorhandene Web-App in eine Android-Hülle zu stecken.
Das geht hier nicht:

- `server/` ist **gebautes** Nitro-Bundle. Der Quelltext der Web-App liegt
  nicht in diesem Repository — nur minifizierte `.mjs`-Dateien mit
  Hash-Namen.
- Die App nutzt serverseitige Funktionen (`createServerFn`). Die
  Electron-Hülle startet dafür einen Node-Prozess auf `127.0.0.1:17321`.
  Android hat keine Node-Laufzeit.

Eine WebView-Hülle bräuchte also einen Server, den jemand betreibt. Die
Apple-Apps kommen ohne aus — sie lesen AniWorld und Serienstream direkt.
Android soll das auch.

## Warum nicht alles in Kotlin

Der geteilte Kern sind rund 3.000 Zeilen: `Models`, `HTML`,
`AniworldClient`, `HosterResolver`, `LibraryStore`. Davon ist der größte Teil
Auswertung fremder HTML-Seiten.

Und genau die ändern sich. In `CLAUDE.md` steht nicht ohne Grund, dass Hoster
ihre Seiten jederzeit ändern und eine fehlgeschlagene Stream-Auflösung
häufig dort liegt und nicht am Nori-Code. Ein zweiter Parser in Kotlin
hieße: jede solche Reparatur zweimal, dauerhaft. Das ist der teuerste Teil
einer Portierung, und er fällt nicht einmal an, sondern immer wieder.

## Was Swift auf Android kann — und was nicht

| | Android |
| --- | --- |
| Foundation, `URLSession` | ✅ über swift-corelibs-foundation |
| SwiftSoup | ✅ reines Swift, keine C-Abhängigkeit |
| Observation (`@Observable`) | ✅ Teil der Toolchain |
| **SwiftUI** | ❌ Apple-eigen, geschlossen — gibt es dort nicht |
| **`Security`** (Schlüsselbund) | ❌ Darwin |
| **`ImageIO`** | ❌ Darwin |

Der wichtigste Punkt steht in der Mitte: **SwiftUI gibt es auf Android
nicht.** „Swift für Android" heißt nicht, dass die App portiert. Geteilt wird
der Kern; Views und Player werden neu gebaut — Compose statt SwiftUI,
Media3/ExoPlayer statt `AVPlayer`.

Das passt zur Architektur, die dieses Projekt ohnehin hat: ein gemeinsamer
Kern, bewusst auseinanderlaufende Oberflächen. Android ist die dritte.

## Die beiden Darwin-Bindungen

Beide liegen in `AniworldClient.swift` und sind gekapselt:

- **`Security`** — der Schlüsselbund in `TMDBKeyStore`. Seit der TMDB-
  Schlüssel eingebaut ist, ist das nur noch Vorrang, kein Muss. Auf Android
  geben `save`, `clear` und `readKeychain` schlicht nichts zurück; ein
  eigener Ablageort (EncryptedSharedPreferences) gehört später in die
  Android-App, nicht in den geteilten Kern — dort wäre er auf Apple toter
  Code.
- **`ImageIO`** — die Prüfung, ob heruntergeladene Bytes ein dekodierbares
  Bild sind. Nötig, weil auch HTTP 200 eine HTML-Fehlerseite tragen kann.
  Auf Apple macht ImageIO das Bild dazu tatsächlich auf; auf Android wird
  die Signatur am Dateianfang gelesen (JPEG, PNG, GIF, WebP, ISO-BMFF für
  AVIF und HEIC). Das erkennt eine Fehlerseite genauso zuverlässig, nur ein
  abgeschnittenes Bild nicht.

Beide Dateien bleiben zwischen iOS und macOS **byte-gleich** —
`tools/check-apple-sources.py` prüft das weiterhin.

## Einrichtung auf dem Runner

Der Android-Durchbau braucht mehr als Xcode:

1. **Swift-SDK für Android.** Ein quergebautes SDK-Bundle von swift.org
   beziehungsweise der Swift-Android-Workgroup:
   ```bash
   swift sdk install <URL-des-Bundles>
   swift sdk list          # muss einen android-Eintrag zeigen
   ```
2. **Android NDK**, passend zur SDK-Version.
3. Für die spätere App zusätzlich das **Android SDK** (Android Studio oder
   die Command-line-Tools) mit akzeptierten Lizenzen.

Prüfen lässt sich Punkt 1 mit:

```bash
tools/require-swift-android.sh
```

## Der Durchbau

`.github/workflows/build-android.yml`, **nur von Hand auslösbar**. Er baut
ausschließlich das Target `NoriCore` — dieselben fünf Dateien, die auch das
Testpaket einbindet:

```bash
cd native
swift build --target NoriCore --swift-sdk <bezeichner>
```

Der Auslöser ist bewusst kein `push`: solange das SDK auf dem Mac nicht
steht, würde das jeden Pull Request rot färben, obwohl am Quelltext nichts
falsch ist. Sobald der Lauf einmal grün war, kann er auf
`native/Nori-macOS/Nori/**` erweitert werden und prüft dann bei jeder
Änderung am Kern mit.

## Material You

Die Compose-Oberfläche nutzt **Material 3 mit dynamischen Farben**. Auf
Compose ist das kein Zusatzaufwand, sondern eine Zeile — `material3` bringt
`dynamicDarkColorScheme(context)` mit, das die Palette aus dem
Hintergrundbild des Nutzers ableitet.

Drei Entscheidungen dazu, damit sie nicht später jemanden überraschen.

### Immer dunkel, aber die Töne vom System

Material You richtet sich normalerweise auch nach der Hell/Dunkel-Einstellung
des Systems. Nori tut das **nicht**: der Inhalt sind Cover, und ein heller
Grund kämpft dagegen an. Genommen wird deshalb immer das dunkle Schema — die
Farbtöne darin kommen aber vom Hintergrundbild.

```kotlin
val scheme = when {
    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && useSystemColors ->
        dynamicDarkColorScheme(LocalContext.current)
    else -> noriDarkScheme   // aus NoriTheme abgeleitet
}
MaterialTheme(colorScheme = scheme, content = content)
```

Dynamische Farben gibt es erst ab **Android 12 (API 31)**. Darunter trägt
`noriDarkScheme` — von Hand aus den Werten in `Theme.swift` abgeleitet, damit
die App auf älteren Geräten aussieht wie ihre Geschwister und nicht wie eine
Vorlage.

### Abschaltbar

`useSystemColors` gehört in die Einstellungen. Wer Noris eigene Farben will,
bekommt sie — die feste Palette ist die Identität der App auf iOS und macOS,
und es wäre seltsam, sie auf Android gar nicht erst anzubieten.

### Nicht im Player

Dort bleiben die Bedienelemente weiß auf Verlauf, so wie auf iOS. Aus dem
Hintergrundbild abgeleitete Farben über bewegtem Bild sind schlecht lesbar,
und der Verlauf trägt die Schrift ohnehin schon.

### Das gekachelte App-Symbol

Der Teil von Material You, den Nutzer tatsächlich bemerken, ist das
eingefärbte Symbol im Launcher (Android 13+). Dafür braucht das adaptive
Symbol eine `<monochrome>`-Ebene in
`res/mipmap-anydpi-v26/ic_launcher.xml`. `tools/make-app-icons.py` erzeugt
die Apple-Symbole schon; die einfarbige Ebene kommt dort dazu.

## Wie es weitergeht

1. **Durchbau** — dieser Schritt. Übersetzt der Kern für Android?
2. **Brücke** — Swift-Kern als `.so`, angebunden über JNI beziehungsweise
   `swift-java`. Erst hier zeigt sich der wirkliche Aufwand.
3. **Oberfläche** — Compose mit Material 3 und dynamischen Farben (siehe
   oben): Startseite, Katalog, Kalender, Merkliste, Detailseite. Media3 für
   den Player.

Punkt 1 ist billig und entscheidet alles Weitere. Scheitert er — etwa weil
SwiftSoup oder Observation für Android nicht durchbauen —, ist eine
Kotlin-Portierung des Kerns die Rückfallebene, und wir wissen es nach einer
Runde statt nach Wochen.
