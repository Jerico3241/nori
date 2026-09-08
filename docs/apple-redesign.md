# Apple-Redesign: Nori × Shirox

Diese Datei hält fest, was beim Redesign der nativen Apple-Oberfläche aus
[Shirox](https://github.com/xibrox/Shirox) übernommen wurde, was Nori-eigen
bleibt und wo bewusst abgewichen wird.

## Leitsatz

> Shirox bestimmt Aussehen, Bewegung und Bedienung. Nori behält Architektur,
> Provider, Datenmodelle und Wiedergabelogik.

Kein Shirox-Code ersetzt funktionierende Nori-Logik. `AniworldClient`,
`HosterResolver`, `LibraryStore`, `CoverIndex` und die AVPlayer-Anbindung
bleiben unangetastet; verändert wurde, was darüber liegt.

## Lizenz und Herkunft

Shirox steht unter der **PolyForm Noncommercial License 1.0.0**. Nori ist ein
privates, nichtkommerzielles Projekt und bleibt es. Zwei Klassen sind zu
unterscheiden:

**Adaptiert (Struktur bzw. Technik aus Shirox übernommen)** — jede dieser
Dateien trägt einen Herkunftshinweis im Kopf:

| Nori | Shirox-Vorlage |
| --- | --- |
| `NoriGlass.swift` (`glassChrome`, `softScrollEdges`) | `Views/Shared/View+GlassChrome.swift` |
| `PlayerMenuButton.swift` (UIKit-`UIMenu` statt SwiftUI-`Menu`) | `Views/Player/PlayerMenuButton.swift` |
| `PlayerSeekOverlay.swift` (Vollflächen-Erkenner, `SingleTouchTapGR`) | `Views/Player/PlayerDoubleTapSeek.swift` |

**Nachgebaut (Prinzip übernommen, für Nori neu geschrieben)** — Bedienleisten,
Fortschrittsregler, Hero, Karten, Bewegungskurven. Diese Dateien enthalten
keinen Shirox-Quelltext.

## Mapping

| Shirox | Nori | Vorgehen |
| --- | --- | --- |
| `View+GlassChrome.swift` | `UI/NoriGlass.swift` | adaptiert, Herkunft vermerkt |
| Streuwerte in den Views | `UI/NoriDesign.swift` | neu: Radien, Abstände, Kurven, Größen |
| `FeaturedCarousel` | `HomeView.HeroCarousel` | Prinzip übernommen: Parallax, Pull-Dehnung, Seitenpunkte als Pillen |
| `FeaturedCard` (Parallax) | `HomeView.HeroSlide` | nachgebaut mit Noris Backdrop/Logo-Logik |
| `PageIndicator` | `NoriPageIndicator` | nachgebaut |
| `HomePressStyle` | `NoriPressStyle` | war schon da, auf Design-Tokens umgestellt |
| `AnimeSection` | `PosterRow` | Kopfzeile mit Akzentbalken übernommen |
| `AnimeCardView` | `CatalogCard` / `NoriGridCard` | Titel ins Bild, Verlauf, feste Kachelform |
| `ContinueWatchingCardDisplay` | `ContinueCard` | Restzeit + Fortschritt beibehalten, Form angeglichen |
| `DetailView` | `SeriesView` | Kopfbereich, Kapselzeile, Folgenkarten |
| `PlayerView` (3182 Zeilen) | `PlayerScreen` + Bausteine | **nicht** übernommen; Nori-Logik bleibt, Aufbau modularisiert |
| `PlayerTopBar` | `PlayerTopBar.swift` | nachgebaut, Glas-Gruppe rechts |
| `PlayerCenterControls` | `PlayerCenterControls.swift` | nachgebaut, zusätzlich `contentTransition` |
| `PlayerBottomBar` | `PlayerBottomBar.swift` | nachgebaut, Nori-Menüs (Hoster/Sprache/Untertitel) |
| `PlayerProgressSlider` | `PlayerProgressSlider.swift` | nachgebaut, ohne Skip-Segmente (hat Nori nicht) |
| `PlayerMenuButton` | `PlayerMenuButton.swift` | adaptiert (UIKit-Menü) |
| `PlayerDoubleTapSeek` | `PlayerSeekOverlay.swift` | adaptiert |
| HLS-Qualität (`HLSQualityPreferenceTests`) | `HLSPlaylist.swift` im Kern | neu geschrieben, mit eigenen Tests |
| `PlayerSkipButton` (85 s) | — | nicht übernommen: Nori kennt keine Intro-Segmente |
| `PlayerVolumeSlider` | — | nicht übernommen: iPhone hat Hardwaretasten |
| `PlayerSubtitleSettingsView` | Untertitelmenü in der Leiste | verkleinert: Nori hat nur AVFoundation-Spuren, keine eigenen Renderer |
| Kingfisher | `CoverImageLoader` | **nicht** übernommen: Nori braucht Referer/User-Agent, hat eigenen Lader |
| `isLocked` (Bildschirmsperre) | — | nicht übernommen, kein Feature-Creep |

## Bewusste Abweichungen von Shirox

Shirox ist Referenz, nicht Obergrenze (§89 des Auftrags). Wo Nori es besser
kann, weicht es ab:

- **Zoom-Übergang.** Shirox benutzt weder `matchedTransitionSource` noch
  `navigationTransition(.zoom:)`. Nori hatte beides schon; es bleibt und wird
  auf die Bedienleisten ausgeweitet.
- **`contentTransition` / `symbolEffect`.** Shirox tauscht Play/Pause hart aus
  (`.animation(nil, value: isPlaying)`). Nori benutzt die native
  Symbolanimation.
- **Haptik.** Shirox hat kein `sensoryFeedback`. Nori setzt es sparsam ein.
- **Reduce Motion.** In Shirox nur an einer Stelle berücksichtigt. In Nori
  laufen alle Bewegungstoken über `NoriMotion`, das `reduceMotion` auswertet.
- **Bildschirmsperre, Cast, Skip-Segmente, Manga.** Nicht Teil von Nori.

## Bewegungssystem

`NoriMotion` in `UI/NoriDesign.swift` ist die einzige Quelle für Kurven:

| Token | Kurve | Zweck |
| --- | --- | --- |
| `press` | `easeOut(0.12)` | Kachel-/Knopfdruck |
| `micro` | `easeOut(0.18)` | Zustandswechsel an einem Element |
| `ui` | `spring(response: 0.32, damping: 0.86)` | Leisten, Kapseln, Pillen |
| `controlsIn` | `spring(response: 0.34, damping: 0.78)` | Bedienung erscheint (nur iOS) |
| `controlsOut` | `easeOut(0.26)` | Bedienung verschwindet (nur iOS) |
| `content` | `spring(response: 0.45, damping: 0.9)` | Hero-, Inhaltswechsel |
| `scrub` | `interactiveSpring(0.3, 0.7)` | Regler unter dem Finger |
| `hover` | `easeOut(0.14)` | Element unter dem Mauszeiger (nur macOS) |

Ein- und Ausblenden sind **absichtlich unsymmetrisch**: lebendig hinein,
ruhig hinaus. Bei aktivem *Bewegung reduzieren* liefert jedes Token `nil`
bzw. eine reine Überblendung — die Funktion ändert sich dabei nicht.

## Liquid Glass

`glassChrome(_:enabled:tint:off:)` ist die einzige Stelle, an der
`glassEffect` vorkommt. Auf iOS/macOS 26+ echtes Liquid Glass mit
`.interactive()`, darunter der klassische Rückfall (Material bzw. getönte
Fläche mit Rand). Eingesetzt wird es gezielt:

- Player: obere Leiste, Mitteltasten, rechte Bedienungsgruppe, Reglerspur
- Startseite: Bereichspillen, „Alle ansehen"-Knöpfe
- Detailseite: Merken-/Menüzeile

**Nicht** an Postern, Karten oder Reihen — dort steht das Artwork im
Mittelpunkt.

## Prüfschritte

```bash
python3 tools/check-apple-sources.py
cd native && swift test
xcodebuild -project native/Nori-iOS/Nori.xcodeproj -scheme Nori \
    -destination 'generic/platform=iOS Simulator' build
xcodebuild -project native/Nori-macOS/NoriMac.xcodeproj -scheme Nori \
    -destination 'platform=macOS' build
```

Liquid Glass braucht das SDK von Xcode 26 oder neuer. Die Workflows
`Build iOS`, `Build macOS` und `Package iOS IPA` fordern das über
`tools/require-xcode.sh 26` ausdrücklich an; ein älterer Mac bricht mit
klarer Meldung ab, statt an `has no member` zu scheitern.

## Was beim Umbau nebenbei aufgefallen ist

Vier Fehler, die es vorher schon gab und die beim Umbau sichtbar wurden:

1. **`timeControlStatus == .playing`** war viermal pro Sekunde falsch: beim
   Puffern steht der Stand auf `.waitingToPlayAtSpecifiedRate`. Das
   Play/Pause-Symbol sprang hin und her, und die Bedienung blendete beim
   Nachladen nicht mehr weg, weil sie sich für angehalten hielt.
2. **SwiftUI-`Menu` im Player** wurde bei jedem Neuzeichnen des Rumpfs
   geschlossen und neu aufgeklappt — der Rumpf zeichnet viermal pro Sekunde.
   Die Hosterliste flackerte, bis sie sich von selbst schloss.
3. **Der Hosterwechsel** ließ die Ansicht auf den Ladebildschirm zurückfallen,
   samt Verlust der Wiedergabeposition im Regler.
4. **Kacheln wurden bei jedem Erscheinen geleert** und neu aufgebaut. Beim
   Zurückscrollen sah eine längst geladene Kachel aus, als lade sie neu.
