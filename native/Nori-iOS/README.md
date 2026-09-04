# Nori für iPhone (SwiftUI)

Native App. Kein Safari, kein Home-Bildschirm-Trick, kein Server.

## IPA (unsigniert)

Die `.ipa` kann **nicht** in der Grok-Umgebung entstehen — dafür braucht es Xcode auf dem Mac.

1. Diesen Ordner auf den Mac mini legen.
2. `IPA-bauen.command` doppelklicken.
3. Es entsteht `Nori.ipa` daneben (arm64, ohne Signatur).
4. IPA aufs iPhone, dort mit Feather / ESign / SideStore signieren und installieren.

Beim ersten Lauf holt Xcode SwiftSoup aus dem Netz.

## Direkt aus Xcode (Kabel)

1. `Nori.xcodeproj` öffnen.
2. Signing: Team = deine Apple-ID.
3. iPhone per Kabel, Entwicklermodus, Run.

## Was drin ist

- Cover zoomt von der Übersicht in die Serie (iOS 18)
- Serienseite färbt sich nach dem Cover
- Weiche Übergänge, reduzierte Bewegung wird beachtet
- Quelle: AniWorld (Anime) oder Serienstream (Serien)
- Katalog, Suche, Kalender, Serie, Staffeln, Folgen
- Merkliste und Fortschritt lokal
- Resume, Haken bei ≥90 %
- Hoster: VOE zuerst, dann Vidmoly / Filemoon
- AVPlayer, HLS direkt, Bild-in-Bild

## Vertrag mit der Web-App

- `contract.json`
- Swift: `Nori/Models.swift`
- Web: `src/lib/aniworld/types.ts` + `src/lib/library.ts` + `src/lib/provider.ts`