# Nori

Anime- und Serien-App. Katalog, Suche, Merkliste, Fortschritt, Player.

Quellen: [AniWorld](https://aniworld.to) (Anime) und [Serienstream](https://serienstream.to) (Serien). Hoster bevorzugt VOE, dann Vidmoly / Filemoon.

**Privat.** Windows-Build liegt unter [Releases](https://github.com/Jerico3241/nori/releases).

Aktuell: **1.8.0** (Windows) · iOS-Quelle im Ordner `native/`.

## Inhalt

| Ordner | Was |
| --- | --- |
| `native/Nori-iOS/` | SwiftUI-App (Xcode). Native Streams über AVPlayer. |
| `desktop/` | Electron-Hülle für Windows (startet den Node-Server, eigenes Fenster). |
| `server/` | Nitro-Build der Web-App (Node). Wird von der Windows-App mitgeliefert. |

Gemeinsames Datenmodell: [`native/Nori-iOS/contract.json`](native/Nori-iOS/contract.json).

## Windows

Fertiges Paket: **Releases → `Nori-Portable-x64.zip`**.

1. ZIP entpacken.
2. Entweder `Installieren.cmd` (legt Nori unter `%LOCALAPPDATA%\Nori` an) oder `Nori.exe` direkt starten (portable).
3. Merkliste und Verlauf liegen im Ordner `Nori-Daten` neben der EXE.

SmartScreen: *Weitere Informationen → Trotzdem ausführen*.

## iPhone

1. `native/Nori-iOS` auf den Mac legen.
2. `IPA-bauen.command` doppelklicken **oder** `Nori.xcodeproj` in Xcode öffnen.
3. Signing: eigene Apple-ID. iPhone per Kabel, Entwicklermodus, Run.
4. Unsignierte IPA mit Feather / ESign / SideStore signieren.

Beim ersten Xcode-Lauf wird SwiftSoup geholt.

## Web-Server lokal

Der Ordner `server/` ist der gebaute Node-Server (kein TypeScript-Quellbaum). Start:

```bash
node server/server/index.mjs
```

Die Electron-Hülle erwartet denselben Server unter `resources/nori-server/` (packaged) bzw. `.output/server/` (dev).

## Hinweis zum Quellcode

Die iOS-App und die Windows-Hülle liegen als lesbarer Quellcode hier. Die Web-Oberfläche (TanStack / React) ist als Nitro-Build unter `server/` enthalten — so läuft Windows 1.8.0. Der TypeScript-Quellbaum der Web-App ist in diesem Stand nicht separat ausgecheckt.

In der iOS-Hoster-Auflösung ist `/redirect/…` (AniWorld) von `/r?t=…` (Serienstream) getrennt, damit Anime-Folgen nicht fälschlich an Serienstream gehen.
