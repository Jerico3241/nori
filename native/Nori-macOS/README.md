# Nori macOS 1.9.0

Native macOS build of the Nori 1.9 SwiftUI client.

## Requirements
- macOS 14 Sonoma or newer
- Xcode 15.4 or newer
- Internet connection

## Run in Xcode
1. Open `NoriMac.xcodeproj`.
2. Let Xcode resolve the SwiftSoup package.
3. Select the `Nori` scheme and `My Mac` as destination.
4. Press `⌘R`.

No Apple Developer membership is required for running the app locally from Xcode. If signing is requested, select your Personal Team under Signing & Capabilities.

## Included
- AniWorld / Serienstream catalog switching
- Catalog, search, calendar, watchlist and history/progress
- Native AVKit playback
- Resume and completed state
- Autoplay next episode countdown
- Language and hoster switching
- Playback speed preferences
- Local library schema v3 with optional iCloud sync code
- Hardened resolver URL validation

## macOS adaptations
- UIKit dependencies replaced with AppKit
- iOS AVPlayerViewController wrapper replaced by SwiftUI `VideoPlayer`
- Native macOS application target (`macosx`), not Mac Catalyst
- macOS-compatible toolbar placements and list styles
- Unsupported iOS zoom/navigation transitions removed from the macOS target
- Complete classic macOS AppIcon asset set (16–1024 px)
- Desktop minimum/default window sizing
- `⌘R` reload command

## Current test status
The project is being tested with Xcode on a real Mac. Recent compatibility fixes removed iOS-only SwiftUI APIs from Home, Watchlist, Calendar, Catalog, Series and Theme and rebuilt the AppIcon asset catalog for macOS.

## Note
The iCloud key-value sync implementation still requires the corresponding Xcode capability/entitlement before it can be considered production-ready.
