# Nori auf Android

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

## Wie es weitergeht

1. **Durchbau** — ✅ **erledigt.** Der geteilte Kern übersetzt für
   `aarch64-unknown-linux-android`.
2. **Brücke** — Swift-Kern als `.so`, angebunden über JNI beziehungsweise
   `swift-java`. Erst hier zeigt sich der wirkliche Aufwand.
3. **Oberfläche** — Compose mit Material 3 und dynamischen Farben (siehe
   oben): Startseite, Katalog, Kalender, Merkliste, Detailseite. Media3 für
   den Player.

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
