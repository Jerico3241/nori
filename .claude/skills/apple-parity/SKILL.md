---
name: apple-parity
description: Regeln für Änderungen an den nativen Apple-Targets von Nori und am gemeinsamen NoriCore.
---

# Apple-Targets und gemeinsamer Kern

## 1. Gemeinsame Kernlogik

Die folgenden Dateien existieren kanonisch nur unter `native/NoriCore/Sources/NoriCore/`:

`Models.swift` · `LibraryStore.swift` · `AniworldClient.swift` · `HosterResolver.swift` · `HTML.swift`

Die gleichnamigen Dateien unter `native/Nori-iOS/Nori/` und `native/Nori-macOS/Nori/` sind Git-Symlinks auf diese Quelle. Änderungen niemals in einem einzelnen Plattformpfad separat vornehmen.

Nach Strukturänderungen prüfen:

```bash
readlink native/Nori-iOS/Nori/Models.swift
readlink native/Nori-macOS/Nori/Models.swift
cd native && swift test
```

`tools/check-apple-sources.py` bleibt als zusätzliche statische Prüfung bestehen.

## 2. Bewusst getrennte UI

`NoriApp.swift` · `Theme.swift` · alle `*View.swift` · plattformspezifische Player-Dateien

| Thema | iOS | macOS |
| --- | --- | --- |
| Navigation | `TabView` | `NavigationSplitView` |
| Einstellungen | App-Tab/Ansicht | `Settings`-Scene (⌘,) |
| Player | iOS-Player / Sheet | eigenes Fenster / AVKit |
| Aktualisieren | `.refreshable` | Toolbar-Knopf + ⌘R |
| Bedienung | Touch/Gesten | Maus, Hover, Kontextmenüs, Shortcuts |
| Erscheinungsbild | mobile UI | dynamische Mac-Farben |

Die Mac-App ist kein wörtlicher Port der iOS-Oberfläche.

## iOS-Muster, die auf dem Mac vermieden werden

- `.refreshable` als einzige Aktualisierung
- `.fullScreenCover`
- `.navigationBarTitleDisplayMode`
- `.navigationBarBackButtonHidden`
- Drag-Gesten als einzige Bedienmöglichkeit
- erzwungenes Farbschema, wenn das Systemerscheinungsbild unterstützt werden soll
- zu kleine adaptive Rasterzellen für Desktop-Fenster

Auf dem Mac gehören stattdessen je nach Kontext `.onHover`, `.contextMenu`, `.help()` und `.keyboardShortcut` dazu.

## API-Decke

| Target | Minimum |
| --- | --- |
| macOS | 14.0 |
| iOS | 17.0 |

Keine APIs verwenden, die das jeweilige Deployment-Target oder das SDK des konfigurierten Xcode-Runners überschreiten.

## Core-Änderungen und CI

Eine Änderung unter `native/NoriCore/**` betrifft immer beide Apple-Apps. Deshalb müssen `Build iOS`, `Build macOS` und `Swift tests` darauf reagieren.

Vor dem Push:

```bash
python3 tools/check-apple-sources.py
cd native && swift test
```
