---
name: apple-parity
description: Regeln für Änderungen an der iOS-App von Nori und am gemeinsamen NoriCore.
---

# iOS-App und gemeinsamer Kern

Seit Nori 2.8.0 gibt es nur noch die iOS/iPadOS-App. Die macOS-App ist
eingestellt; ihr Quelltext liegt nur noch in der Git-Geschichte.

## 1. Kernlogik

Die folgenden Dateien existieren kanonisch nur unter `native/NoriCore/Sources/NoriCore/`:

`Models.swift` · `LibraryStore.swift` · `AniworldClient.swift` · `HosterResolver.swift` · `HTML.swift`

Die gleichnamigen Dateien unter `native/Nori-iOS/Nori/` sind Git-Symlinks auf diese Quelle. Änderungen niemals im iOS-Pfad separat vornehmen.

Nach Strukturänderungen prüfen:

```bash
readlink native/Nori-iOS/Nori/Models.swift
cd native && swift test
```

`tools/check-apple-sources.py` prüft zusätzlich statisch, dass jede dieser Dateien ein Symlink auf den Kern ist.

## 2. API-Decke

| Target | Minimum |
| --- | --- |
| iOS | 17.0 |

Keine APIs verwenden, die das Deployment-Target oder das SDK des konfigurierten Xcode-Runners überschreiten; neuere APIs nur hinter `#available`.

## Core-Änderungen und CI

Eine Änderung unter `native/NoriCore/**` betrifft die iOS-App. Deshalb müssen `Build iOS` und `Swift tests` darauf reagieren. Beide laufen auf `macos-26`; das Projekt ist privat und die Minuten sind knapp, also keine zusätzlichen Auslöser.

Vor dem Push:

```bash
python3 tools/check-apple-sources.py
cd native && swift test
```
