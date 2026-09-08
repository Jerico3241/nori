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

Der Android-Durchbau braucht mehr als Xcode. Vier Schritte, und zwei davon
sind Fallen, die sich als Fehler im Quelltext tarnen:

1. **Open-Source-Toolchain von swift.org.** Nicht die aus Xcode. Ein
   Cross-Compilation-SDK verlangt die offene Toolchain in **exakt** der
   Version des SDK-Bundles. Xcodes Toolchain kommt trotzdem durch
   `swift sdk list` — die SDK-Liste liegt im Benutzerverzeichnis und weiß
   nichts von der Toolchain. Der Build läuft dann los und scheitert an
   dutzenden Fehlern, die nach kaputtem Quelltext aussehen.

   Ausgewählt wird sie über `TOOLCHAINS`:

   ```bash
   export TOOLCHAINS=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
     ~/Library/Developer/Toolchains/swift-6.3.3-RELEASE.xctoolchain/Info.plist)
   ```

2. **Android NDK**, r27d oder neuer.

3. **Swift-SDK für Android**, in derselben Version wie die Toolchain:

   ```bash
   swift sdk install https://download.swift.org/swift-6.3.3-release/android-sdk/\
swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz \
     --checksum d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5
   ```

4. **Das SDK gegen das NDK einrichten.** Das Bundle zeigt über
   `sdkRootPath: ndk-sysroot` auf ein Verzeichnis, das es *nicht mitbringt* —
   es entsteht erst durch ein Skript, das im Bundle selbst liegt. Fehlt der
   Schritt, bricht der Build mitten in SwiftSoup mit
   „`'semaphore.h' file not found`" ab:

   ```bash
   export ANDROID_NDK_HOME=/opt/homebrew/share/android-commandlinetools/ndk/<version>
   bash ~/Library/org.swift.swiftpm/swift-sdks/\
swift-6.3.3-RELEASE_android.artifactbundle/swift-android/scripts/setup-android-sdk.sh
   ```

Für die spätere App kommt das **Android SDK** dazu (Android Studio oder die
Command-line-Tools) mit akzeptierten Lizenzen.

Alle vier Punkte prüft:

```bash
tools/require-swift-android.sh
```

Es vergleicht inzwischen auch Toolchain-Version gegen SDK-Version und besteht
auf dem eingerichteten `ndk-sysroot` — beides, weil ein Fehlschlag sonst erst
im Build auffällt und dort nach etwas ganz anderem aussieht.

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

1. **Durchbau** — ✅ **erledigt.** Der geteilte Kern übersetzt für
   `aarch64-unknown-linux-android`.
2. **Brücke** — ✅ **gebaut.** Siehe unten.
3. **Oberfläche** — ✅ **gebaut.** Compose mit Material 3 als Grundlage, aber
   mit den Nori-Farben aus `Theme.swift` statt der Material-Vorgaben. Media3
   für den Player.

Punkt 1 war billig und hat alles Weitere entschieden. Das Ergebnis:

> `Build of target: 'NoriCore' complete!`

SwiftSoup, Observation und Foundation bauen für Android durch. **Die
Kotlin-Rückfallebene entfällt** — der geteilte Kern trägt, und die Parser für
AniWorld und Serienstream müssen nicht ein zweites Mal geschrieben und
danach dauerhaft doppelt repariert werden. Genau das war die teure Frage.

Nötig war dafür genau eine Änderung am Quelltext, und sie steht in derselben
Reihe wie `Security` und `ImageIO` weiter oben: `URLSession` und alles, was
daran hängt, liegt außerhalb von Apple im Modul `FoundationNetworking`.
`AniworldClient.swift` und `HosterResolver.swift` importieren es jetzt über
`#if canImport(FoundationNetworking)` — auf Apple wirkungslos, für Android
der Unterschied zwischen 50 Fehlern und einem grünen Build.

Die dritte Darwin-Bindung ist damit auch benannt; die Tabelle „Was Swift auf
Android kann" oben nennt `URLSession` als vorhanden, was stimmt — nur eben
aus einem anderen Modul.

## Die Brücke

```text
Compose UI
   │
Kotlin ViewModels · Repositories
   │
NoriCore.kt                       getippter Zugang, alles suspend
   │  NoriBridge.nativeCall(ByteArray): ByteArray
nori_jni.c                        JNI-Hülle, rund 40 Zeilen
   │  nori_bridge_call(const char *): const char *
NoriBridge.swift                  #if os(Android)
   │
AniworldClient · HosterResolver · LibraryStore · HTML
```

### Warum JSON durch eine einzige C-Funktion

Über JNI ließen sich auch Objekte reichen. Das hieße: für jedes Modell eine
Java-Klasse, für jedes Feld ein Getter, und bei jeder Änderung an
`Models.swift` dieselbe Änderung noch zweimal. Genau das soll die Portierung
vermeiden — es ist derselbe Grund, aus dem der Kern nicht in Kotlin
nachgebaut wird.

Die Modelle sind bereits `Codable`. Damit ist die billigste tragfähige Grenze
eine Funktion, die JSON hinein und JSON heraus reicht:

```c
const char *nori_bridge_call(const char *request);
void        nori_bridge_free(char *response);
```

Kotlin liest dieselben Felder mit kotlinx.serialization. Kommt in
`Models.swift` ein optionales Feld dazu, baut **beides** weiter durch, ohne
dass jemand etwas nachträgt.

Der Preis steht auch fest: ein Katalog mit mehreren tausend Einträgen wird bei
jedem Gang über die Brücke vollständig kodiert und dekodiert. Deshalb liegt
diesseits ein Zwischenspeicher (`CatalogRepository`) — die Kosten fallen
einmal je Quelle an, nicht je Bildschirm.

### Byte-Felder statt Strings

`GetStringUTFChars` und `NewStringUTF` arbeiten mit *modified UTF-8*. Das
unterscheidet sich vom echten UTF-8 bei allem jenseits der BMP — bei einem
Emoji in einem Serientitel kämen vier Bytes an, wo sechs erwartet werden.
Übertragen werden deshalb `ByteArray`s; kodiert wird auf beiden Seiten mit
echtem UTF-8.

### Blockierend, mit Absicht

Der Kern ist durchgängig `async`, eine C-Funktion ist es nicht. Der Aufruf
startet eine Task und wartet auf einem Semaphor. Das ist zulässig, weil der
aufrufende Thread ein JNI-Thread aus Kotlins `Dispatchers.IO` ist und nicht
zum kooperativen Pool von Swift Concurrency gehört: die Task läuft auf einem
anderen Thread weiter, blockiert wird nur der Anrufer. Auf Kotlin-Seite steht
jeder Aufruf in `withContext(Dispatchers.IO)`, mit einem Deckel von zwölf
gleichzeitigen Aufrufen.

### Kein NDK im Gradle-Build

`nori_jni.c` ist ein C-Target derselben SwiftPM-Paketbeschreibung und landet
mit NoriCore in einer `libNoriAndroid.so`. Gradle kopiert die fertige Datei
nach `jniLibs` — kein CMake, kein `externalNativeBuild`, keine zweite
Toolchain-Einrichtung für jeden, der die App baut.

### Die Swift-Laufzeit muss mit

Auf Android ist sie **kein** Systembestandteil. `libswiftCore.so`,
`libFoundation.so`, `libFoundationNetworking.so`, `libswift_Concurrency.so`
und `libc++_shared.so` müssen in die APK, sonst stirbt die App beim
`System.loadLibrary` — ein Fehler, der auf dem Entwicklerrechner nie
auftritt. `tools/collect-android-libs.py` sammelt sie aus dem SDK-Bündel und
bricht mit Namensliste ab, statt eine unvollständige APK durchzulassen.

### Die API-Ebene muss zu `minSdk` passen

Das Swift-SDK bietet Tripel von `android28` bis `android36`. Gegen 36 gebaut
setzt der Compiler `__ANDROID_API__=36` und darf Symbole verwenden, die es
auf einem Gerät mit Android 9 nicht gibt. Die APK ließe sich dort
installieren und stürbe beim Laden. `tools/android-triples.py --api 28` wählt
deshalb ausdrücklich die Ebene, die `minSdk` in `app/build.gradle.kts`
verlangt — nicht die höchste verfügbare.

## Die App

```text
native/Nori-Android/
├── settings.gradle.kts
├── gradle/libs.versions.toml     alle Fassungen an einer Stelle
├── jni/                          C-Hülle, Teil des SwiftPM-Pakets
└── app/src/main/
    ├── kotlin/de/nori/
    │   ├── core/                 Brücke, Modelle, getippter Zugang
    │   ├── data/                 Repositories, ein Bibliotheksstand
    │   ├── player/               Media3, Spuren, MediaSession
    │   └── ui/                   Compose: Start, Suche, Detail, Bibliothek,
    │                             Einstellungen, Player
    └── jniLibs/                  wird vom Build gefüllt, nicht eingecheckt
```

### Ein Zustand, nicht zwei

Merkliste, Verlauf, Fortschritt und Einstellungen liegen im Kern. Jede
Änderung geht dorthin und gibt den **vollständigen** Stand zurück, den die App
in genau einem `StateFlow` hält. Das ist die Antwort auf einen Fehler, den man
in Compose leicht baut: jeder Bildschirm mit eigenem `mutableStateOf`, und die
Merkliste zeigt einen Titel noch als gemerkt, den die Detailseite gerade
entfernt hat.

Auch die Regeln kommen von dort. „Ab 90 % gilt als gesehen" und „unter acht
Sekunden kein Fortsetzen" sind keine Anzeigedetails; in Kotlin nachgebaut
liefen sie früher oder später auseinander.

### Der Player

Er kennt weder AniWorld noch VOE. Er bekommt eine fertige `PlaySource` und
spielt sie:

```text
Episode → NoriCore.watch      → Hoster
        → NoriCore.resolveBest → PlaySource (URL + Kopfzeilen)
        → NoriMediaSourceFactory → Media3
```

Die Kopfzeilen sind der Punkt, an dem eine Portierung still scheitert: viele
Hoster liefern das Video nur aus, wenn der Abruf denselben `Referer` und
`User-Agent` mitbringt wie der Abruf der Einbettungsseite. Media3 schickt von
sich aus nur seinen eigenen User-Agent. Sie entstehen deshalb im Kern — aus
derselben Quelle, mit der die Adresse gefunden wurde — und gehen über
`OkHttpDataSource.setDefaultRequestProperties` unverändert weiter.

Ein Hosterwechsel merkt sich die Stelle, löst neu auf, tauscht die
MediaSource und setzt die Stelle zurück. Die Folge wird nicht neu geöffnet,
der Fortschritt nicht angefasst.

Wiedergabefehler werden eingeordnet statt durchgereicht: 401/403 und 404
heißen „anderer Hoster", 429 und 5xx heißen „nochmal versuchen", ein
Parserfehler heißt meist „der Hoster hat eine Fehlerseite geschickt". Danach
richtet sich, was der Player anbietet.

### CloudStream als Referenz

CloudStream 4.8.0 (Commit `8bdc599`) beantwortet gut, *welche* Android-APIs
so ein Player braucht und welche Fallstricke es bei HLS, Kopfzeilen und
Spurauswahl gibt. Übernommen wurde daraus **kein Code** — CloudStream steht
unter GPLv3, und Nori soll kein Derivat werden.

## Bauen

Auf dem self-hosted Mac über `.github/workflows/build-android-app.yml`, in
zwei Stufen:

1. **`core`** — `libNoriAndroid.so` je ABI, mit dem Swift-SDK für Android.
2. **`apk`** — Gradle. Der Lauf holt sich vorher ein eigenes JDK 21 und das
   Android-SDK nach `~/Library/Android` (`tools/android-sdk.sh`); das
   System-Java des Runners bleibt unangetastet.

Von Hand, mit eingerichteter Toolchain:

```bash
cd native
swift build -c release --product NoriAndroid \
  --swift-sdk aarch64-unknown-linux-android28
python3 ../tools/collect-android-libs.py --help

cd Nori-Android
./gradlew assembleDebug
./gradlew assembleRelease
```

Danach prüft `python3 tools/check-android-apk.py`, ob in der Release-APK
tatsächlich steht, was drinstehen muss: die Bibliothek für beide ABIs, die
vollständige Swift-Laufzeit, das exportierte JNI-Symbol und die von R8
verschonte Brücke im DEX. Ein grüner Gradle-Lauf beweist keins davon.

## Unterstützte ABIs

| ABI | Stand |
| --- | --- |
| `arm64-v8a` | gebaut — das ist die ABI echter Geräte |
| `x86_64` | gebaut — für den Emulator |
| `armeabi-v7a` | nicht gebaut; das SDK könnte es, aber 32-Bit-Geräte sind kein Ziel |

`abiFilters` in `app/build.gradle.kts` nennt genau die beiden gebauten. Eine
dritte stillschweigend mitzupacken hieße: eine APK, die auf dem Gerät am
fehlenden `libNoriAndroid.so` stirbt.

## Bekannte Einschränkungen

- **Android TV ist vorbereitet, nicht fertig.** Die Architektur verbaut es
  nicht — der Player hängt nicht an Touch, die ViewModels wissen nichts von
  der Oberfläche, und `LEANBACK_LAUNCHER` steht im Manifest. Eine eigene
  TV-Oberfläche mit Fokusführung gibt es aber noch nicht.
- **Untertitel kommen nur aus dem Stream selbst.** Der Kern liefert keine
  externen Untertiteldateien; was Media3 an eingebetteten Spuren findet, ist
  wählbar, mehr nicht.
- **Kein eigener Ablageort für einen TMDB-Schlüssel.** Auf Apple liegt er im
  Schlüsselbund; auf Android trägt bis auf Weiteres der eingebaute Schlüssel.
  Ein eigener Ort (EncryptedSharedPreferences) gehört in die Android-App,
  nicht in den geteilten Kern.
- **Keine Synchronisation.** Wie auf Apple: `LibrarySyncProvider` ist da,
  angebunden ist nichts.
