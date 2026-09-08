# Hinweise zu fremdem Code

## Shirox

Die native Apple-Oberfläche von Nori orientiert sich an
[Shirox](https://github.com/xibrox/Shirox) — Gestaltung, Bewegung und
Bedienung. Der größte Teil davon ist nachgebaut, nicht übernommen: die
Bedienleisten des Players, der Fortschrittsregler, der Kopfbereich der
Startseite und die Karten sind für Noris Datenmodell neu geschrieben.

An drei Stellen ist Shirox-Quelltext tatsächlich Vorlage gewesen und in
angepasster Form übernommen worden:

| Nori | Shirox |
| --- | --- |
| `native/*/Sources/UI/NoriGlass.swift` | `Shirox/Views/Shared/View+GlassChrome.swift` |
| `native/Nori-iOS/Sources/Features/Player/PlayerMenuButton.swift` | `Shirox/Views/Player/PlayerMenuButton.swift` |
| `native/Nori-iOS/Sources/Features/Player/PlayerSeekOverlay.swift` | `Shirox/Views/Player/PlayerDoubleTapSeek.swift` |

Diese Dateien tragen den Hinweis auch im Kopf.

Shirox steht unter der **PolyForm Noncommercial License 1.0.0**:
<https://polyformproject.org/licenses/noncommercial/1.0.0>

> Required Notice: Copyright 2026 xibrox (https://github.com/xibrox/Shirox)

Die Lizenz erlaubt Nutzung, Änderung und Weitergabe für nichtkommerzielle
Zwecke. Nori ist ein privates, nichtkommerzielles Projekt und wird nicht
verkauft, nicht vermarktet und nicht in einem Erwerbszusammenhang betrieben.
Sollte sich das je ändern, müssen diese drei Dateien vorher ersetzt werden.

## SwiftSoup

HTML-Parser der Apple-Apps, MIT-Lizenz:
<https://github.com/scinfu/SwiftSoup>
