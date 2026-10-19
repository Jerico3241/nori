# Nori auf Android

> **Stand Nori 2.8.0:** macOS, Windows und LG webOS sind eingestellt und aus
> dem Repository entfernt. Was hier über diese Plattformen, den
> TypeScript-Kern (`shared/`) oder den Nori-Server steht, beschreibt den
> früheren Stand und bleibt als Begründung stehen.

Der Plan in einem Satz: **der geteilte Kern bleibt Swift, die Oberfläche wird
Compose.**

## Warum nicht die Web-App verpacken

Naheliegend wäre, die vorhandene Web-App in eine Android-Hülle zu stecken.
Das geht hier nicht:

Gemeint war damit die frühere Windows-Fassung: ein gebautes Nitro-Bundle mit
serverseitigen Funktionen (`createServerFn`), dessen Quelltext nie in diesem
Repository lag, und eine Electron-Hülle, die dafür einen Node-Prozess auf
`127.0.0.1:17321` startete. Beides ist mit Windows 2.0.0 entfallen.

Was seitdem unter `apps/windows/` steht, ist Quelltext — aber es hilft
Android nicht weiter: Die Quellenschicht läuft dort im **Hauptprozess** von
Electron, also in Node. Eine WebView unter Android hat keine Node-Laufzeit,
und eine WebView allein kommt an AniWorld und Serienstream nicht heran —
fremde Herkunft, kein `Referer`, keine lesbaren Weiterleitungen. Es bliebe
ein Server, den jemand betreibt. Die Apple-Apps kommen ohne aus; Android soll
das auch.

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

## Bauen

`.github/workflows/build-android.yml` („Build Android"), **nur von Hand**:
*Actions → Build Android → Run workflow*. Er läuft auf einem Linux-Runner von
GitHub (`ubuntu-latest`, derzeit 24.04), nicht auf einem Mac — weder der Swift-Kern für
Android noch Gradle braucht einen, und ein Mac-Runner zählt bei einem privaten
Repository zehnfach. Die erste Fassung im September lief auf dem self-hosted Mac; den
gibt es nicht mehr.

Kein `push`-Auslöser, mit Absicht: die Minuten sind begrenzt, gebaut wird
einmal je fertigem Stand. Aus demselben Grund nimmt `Swift tests` die
Kotlin-Oberfläche (`native/Nori-Android/**` außer `jni/`) von seinen Pfaden aus.

Der Lauf, in dieser Reihenfolge:

1. **Open-Source-Swift von swift.org** in exakt der Fassung des SDK-Bündels
   (`SWIFT_VERSION` im Workflow, derzeit 6.3.3). Eine abweichende Toolchain
   baut los und scheitert an dutzenden Fehlern, die nach kaputtem Quelltext
   aussehen.
2. **Swift-SDK für Android**, geprüft gegen die Prüfsumme im Workflow.
3. **Das SDK gegen das NDK einrichten.** Das Bündel zeigt über
   `sdkRootPath: ndk-sysroot` auf ein Verzeichnis, das es *nicht mitbringt* —
   es entsteht erst durch `swift-android/scripts/setup-android-sdk.sh` im
   Bündel selbst. Fehlt der Schritt, bricht der Build mitten in SwiftSoup mit
   „`'semaphore.h' file not found`" ab. Das NDK bringt der Runner mit
   (`ANDROID_NDK_LATEST_HOME`, r27d oder neuer).
4. **`libNoriAndroid.so` je ABI**, gegen API-Ebene 28
   (`tools/android-triples.py --api 28`, siehe unten).
5. **Einsammeln** mit `tools/collect-android-libs.py`: Bibliothek plus
   Swift-Laufzeit nach `jniLibs`, gestrippt mit `llvm-strip` aus dem NDK.
6. **Gradle** `assembleRelease` mit dem JDK 21 und dem Android-SDK des
   Runners.
7. **`tools/check-android-apk.py`** prüft, ob in jeder APK steht, was
   drinstehen muss: die Bibliothek für beide ABIs, die vollständige
   Swift-Laufzeit, das exportierte JNI-Symbol und die von R8 verschonte Brücke
   im DEX. Ein grüner Gradle-Lauf beweist keins davon.

Am Ende hängt `Nori-Android-v<VERSION>.apk` (arm64, für echte Geräte) als
Artefakt am Lauf, drei Tage lang.

Von Hand, mit eingerichteter Toolchain:

```bash
cd native
swift build -c release --product NoriAndroid \
  --swift-sdk aarch64-unknown-linux-android28
python3 ../tools/collect-android-libs.py --help

cd Nori-Android
./gradlew assembleRelease
```

### Versionsnummer

Android führt **keine eigene Nummer**. `app/build.gradle.kts` liest
`MARKETING_VERSION` und `CURRENT_PROJECT_VERSION` aus dem iOS-Projekt — die
Stelle, die `tools/nori-version.py` setzt. Die Buildnummer wird zum
`versionCode`; sie steigt mit jedem `bump`, und Android installiert eine
Fassung nur über eine mit kleinerem `versionCode`. `native/Nori-Android` und
`native/Package.swift` zählen für `nori-version.py check` als Paketinhalt.

### Signatur

Die Release-APK ist mit dem Debug-Schlüssel des Runners signiert. Der
entsteht bei jedem Lauf neu, und Android lehnt ein Update mit fremder
Signatur ab: **bis es einen festen Schlüssel gibt, muss die alte Fassung vor
dem Installieren einer neuen entfernt werden** (die Merkliste geht dabei
verloren). Ein fester Schlüssel als GitHub-Secret gehört zum Schritt in den
gemeinsamen Release.

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

## Google-Drive-Abgleich

Der Abgleich über Google Drive ist im geteilten Kern fertig und übersetzt für
Android mit — ausdrücklich auch die Kryptografie: SHA-256 für PKCE ist von Hand
geschrieben und benutzt **nicht** `CryptoKit`, das es hier nicht gibt.

Fertig und mitübersetzt:

| Datei | Inhalt |
| --- | --- |
| `LibrarySync.swift` | Schema v6, Migration, Zusammenführung |
| `LibrarySyncEngine.swift` | Ablauf, Zeitplan, Fehlerbehandlung |
| `GoogleDrive.swift` | Drive-Client, Wiederholungen, Backoff |
| `GoogleOAuth.swift` | PKCE, Tokentausch, Erneuern, Widerruf |
| `NoriSync.swift` | Zusammenbau |

Was fehlt, sind vier kleine Klassen, und alle vier können nur in der
Android-App liegen — im geteilten Kern wären sie auf Apple toter Code, genau
wie `Security` und `ImageIO` weiter oben:

1. **`GoogleTokenStore`** über `EncryptedSharedPreferences` mit einem Schlüssel
   aus dem **Android-Keystore**. `KeychainTokenStore` gibt außerhalb von Apple
   nichts zurück (`#if canImport(Security)`), und `SharedPreferences` allein ist
   für einen Auffrischungstoken der falsche Ort.
2. **`GoogleSignInPresenter`** über Googles **Authorization API**
   (`com.google.android.gms:play-services-auth`): ein `AuthorizationRequest`
   mit `setRequestedScopes(listOf(Scope("https://www.googleapis.com/auth/drive.appdata")))`
   und `requestOfflineAccess(serverClientId)`, gestartet über den
   `PendingIntent` aus `AuthorizationResult`.

   Der **Credential Manager** ist dafür ausdrücklich nicht der richtige
   Baustein: er beantwortet „wer ist das?", nicht „darf Nori an den
   App-Ordner?". Für den Drive-Zugriff braucht es eine Autorisierung, keine
   Authentifizierung. **Kein Firebase** — Drive braucht es nicht. **Kein
   eingebetteter Browser** — Google lehnt Anmeldungen in einer WebView ab.
3. **`SyncBookkeeping`** über `SharedPreferences`.
4. Der Aufruf von `GoogleDriveSync` aus der Compose-Oberfläche und die Anbindung
   an den Lebenszyklus.

Dazu kommen **zwei** Dinge in der Google Cloud, beide im selben Projekt wie die
übrigen Clients (`docs/google-drive-sync.md`):

- ein OAuth-Client vom Typ **Android** mit Paketname und SHA-1-Fingerabdruck
  des Signaturschlüssels,
- ein OAuth-Client vom Typ **Web**, dessen Client-ID an
  `requestOfflineAccess(serverClientId)` geht. Ohne sie gibt Google keinen
  Auffrischungstoken heraus, und die Verbindung hielte eine Stunde — dasselbe,
  was `GoogleAuthorization.signIn` auf Apple mit `noRefreshToken` abfängt.

Und eine Build-Einstellung: die Client-IDs gehören **nicht** in den Quelltext.
Der Weg ist derselbe wie `GOOGLE_CLIENT_ID` auf Apple — ein `buildConfigField`
aus einer nicht eingecheckten `local.properties`.

### Wie die Oberfläche aussehen soll

Dieselbe wie überall sonst, und das ist der Punkt:

```text
Einstellungen → Synchronisation → [ Mit Google anmelden ]
        ↓
Kontoauswahl von Google, einmal bestätigen
        ↓
verbunden — [ Jetzt synchronisieren ]  [ Dieses Gerät trennen ]
```

**Kein Feld für eine Client-ID, keine Tokens, keine technischen Einstellungen.**
Gilt die Berechtigung nicht mehr, steht dort „Google Drive muss erneut verbunden
werden" und ein Knopf — der Zustand heißt im Kern `needsReauthorization` und ist
schon da.

Die Arbeit liegt damit in der Compose-App und nicht im Abgleich. **Solange diese
vier Klassen fehlen, gibt es auf Android keinen Abgleich**, und nichts in diesem
Repository behauptet etwas anderes.

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

## Unterstützte ABIs

| ABI | Stand |
| --- | --- |
| `arm64-v8a` | gebaut — das ist die ABI echter Geräte |
| `x86_64` | gebaut — für den Emulator |
| `armeabi-v7a` | nicht gebaut; das SDK könnte es, aber 32-Bit-Geräte sind kein Ziel |

`abiFilters` in `app/build.gradle.kts` nennt genau die beiden gebauten. Eine
dritte stillschweigend mitzupacken hieße: eine APK, die auf dem Gerät am
fehlenden `libNoriAndroid.so` stirbt.

## Warum die APK so groß ist

| Datei | Größe |
| --- | --- |
| `app-arm64-v8a-release.apk` | 74 MB |
| `app-x86_64-release.apk` | 76 MB |
| `Nori-Android-release.apk` (universell) | 146 MB |

Die Swift-Laufzeit wiegt je Architektur rund 25 MB und muss mitgeliefert
werden — auf Android ist sie kein Systembestandteil. In der universellen APK
liegt sie zweimal, obwohl jedes Gerät nur eine davon benutzt; deshalb die
Aufteilung nach ABI.

Zwei Dinge sind dabei nicht selbstverständlich:

- **Gestrippt wird beim Einsammeln, nicht von AGP.** Ohne NDK im Android-SDK
  meldet AGP nur „Unable to strip the following libraries, packaging them as
  they are" und packt die vollständigen Debugsymbole ein — das waren 247 MB
  statt 146. `tools/collect-android-libs.py` ruft deshalb `llvm-strip` aus dem
  NDK auf. `--strip-unneeded` lässt `.dynsym` unangetastet, also genau die
  Tabelle, über die der Lader die Brücke findet.
- **Das ist der Preis der Architektur.** Ein in Kotlin nachgebauter Kern wäre
  ein paar hundert Kilobyte groß. Er müsste aber bei jeder Änderung an
  AniWorld oder Serienstream ein zweites Mal repariert werden — und genau das
  ist der teure Teil, nicht die Dateigröße.

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

## Wie es weitergeht

Der Plan vom 19.10.2026, mit Salvatore abgestimmt:

1. **Die September-App wieder anschließen** — auf den Stand von Nori 2.9.0
   gebracht, Bau auf Linux. ✅ mit Nori 2.9.0.
2. **Erster Test auf einem echten Gerät.** Bisher ist die App auf keinem
   Gerät gelaufen; ob AniWorld antwortet, ein Hoster einen Stream liefert und
   Media3 ihn abspielt, ist damit nicht gezeigt.
3. **Fehler beheben und an iOS angleichen** — was iOS seit September dazu
   gelernt hat (Startseite und Katalog aus `HomeFeed`/`CatalogFeed`,
   Wiedergabe-Markierungen, Kalender mit `hasTime`).
4. **Google-Drive-Abgleich** — die vier Klassen oben und zwei OAuth-Clients.
5. **Gemeinsamer Release** — `Nori-Android-v<VERSION>.apk` im Release, mit
   festem Signaturschlüssel.
6. **Google TV** — eigene Oberfläche für drei Meter Abstand und Steuerkreuz,
   auf denselben ViewModels und demselben Player. `LEANBACK_LAUNCHER` steht
   schon im Manifest.
