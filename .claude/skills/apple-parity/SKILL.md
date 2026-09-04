---
name: apple-parity
description: Regeln für Änderungen an den nativen Apple-Targets von Nori (native/Nori-iOS, native/Nori-macOS) — welche Dateien zwischen iOS und macOS geteilt sind und identisch bleiben müssen, welche bewusst auseinanderlaufen, und welche iOS-Muster auf dem Mac nicht funktionieren. Verwenden, sobald Swift-Code unter native/ angefasst wird, ein Feature in beide Apple-Apps soll, oder eine der beiden Apps sich "wie ein Port" anfühlt.
---

# Apple-Targets: was geteilt wird und was nicht

Nori hat zwei getrennte Xcode-Projekte mit teilweise gleichen Dateinamen.
**Gleicher Dateiname heißt nicht gleicher Inhalt.** Vor jeder Änderung
einsortieren, in welche der drei Klassen die Datei fällt.

## 1. Wortgleich geteilt — Änderung immer in beide Targets

`Models.swift` · `LibraryStore.swift` · `AniworldClient.swift` · `HosterResolver.swift`

Diese vier Dateien enthalten keine einzige plattformspezifische Zeile und sind
Byte für Byte identisch. Wer eine davon nur in einem Target ändert, erzeugt
still divergierende Datenmodelle — der Bibliotheksstand wird dann zwischen
iPhone und Mac über iCloud inkompatibel.

Nach der Änderung:

```bash
diff native/Nori-iOS/Nori/<Datei> native/Nori-macOS/Nori/<Datei>   # muss leer sein
```

## 2. Logisch geteilt, unterschiedlich formuliert

`HTML.swift`

Beide Fassungen parsen dasselbe HTML, aber die macOS-Fassung wurde
umstrukturiert (lange Optional-Ketten in Zwischenvariablen aufgelöst, um
Typechecker-Timeouts zu vermeiden). Sie sind deshalb **nicht** byte-gleich —
trotzdem gehört jede Änderung an der Parsing-Logik in beide Targets, sonst
bricht die Stream-Auflösung auf genau einer Plattform.

`tools/check-apple-sources.py` vergleicht hier die Menge der Deklarationen und
meldet, wenn eine Funktion nur in einem Target existiert.

## 3. Bewusst getrennt — nicht angleichen

`NoriApp.swift` · `Theme.swift` · alle `*View.swift` · `PlayerScreen.swift`

Die macOS-Oberfläche folgt seit dem Umbau Desktop-Konventionen und ist **kein**
Spiegel der iOS-Oberfläche mehr. Diese Dateien anzugleichen macht die
Mac-App wieder kaputt.

| Thema | iOS | macOS |
| --- | --- | --- |
| Navigation | `TabView` + `.tabItem` | `NavigationSplitView` mit Seitenleiste |
| Quellenumschalter | `KindSwitch` (Drag-Kapsel) | segmentierter `Picker` in der Seitenleiste |
| Einstellungen | Tab „Mehr" | `Settings`-Scene (⌘,) mit Tab-Bereichen |
| Player | `.sheet` | eigene `Window`-Scene über `PlayerHost` |
| Neu laden | `.refreshable` | Toolbar-Knopf + ⌘R über `focusedSceneValue` |
| Farben | fest dunkel | `NSColor(name:dynamicProvider:)`, folgt dem System |
| Listen | `.listRowBackground` | `.listStyle(.inset(alternatesRowBackgrounds: true))` |

## iOS-Muster, die auf dem Mac ins Leere greifen

Kompilieren teils anwendungslos, deshalb fallen sie ohne Prüfung nicht auf:

- `.refreshable` — Pull-to-Refresh existiert auf macOS nicht. Ohne
  Toolbar-Knopf ist die Ansicht **gar nicht** neu ladbar.
- `.preferredColorScheme(.dark)` — ignoriert die Systemeinstellung.
- `.listRowBackground` / `.scrollContentBackground(.hidden)` — übermalt die
  native Auswahlmarkierung.
- `.fullScreenCover`, `.navigationBarTitleDisplayMode`,
  `.navigationBarBackButtonHidden` — iOS-only.
- Drag-Gesten als einzige Bedienung eines Schalters — auf dem Mac gibt es
  einen Mauszeiger, keine Wischgeste.
- Zu kleine Rasterzellen (`GridItem(.adaptive(minimum: 110))`) — auf einem
  1280 px breiten Fenster briefmarkengroß.

Umgekehrt gehört auf den Mac dazu, was iOS nicht kennt: `.onHover`,
`.contextMenu`, `.help()`-Tooltips, `.keyboardShortcut`.

## API-Decke

| Target | Minimum | Bedeutung |
| --- | --- | --- |
| macOS | 14.0 | keine macOS-15-APIs (`Tab`-basiertes `TabView`, `.sidebarAdaptable`, `.toolbar(removing:)`, `.searchFocused`) |
| iOS | 17.0 | |

`SWIFT_VERSION = 5.0` ist der Sprachmodus, nicht die Compilerversion —
`if`/`switch`-Ausdrücke und Makros stehen zur Verfügung.

## Vor dem Push

```bash
python3 tools/check-apple-sources.py
```

Ersetzt keinen Build. Der einzige echte Typechecker ist der
GitHub-Actions-Lauf `Build macOS`; siehe `.claude/skills/steward/SKILL.md`.
