# Nori macOS 1.9.0

Native macOS test build of the Nori 1.9 SwiftUI client.

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
- Local library migration v1 -> v2
- Hardened resolver URL validation

## macOS adaptations
- UIKit dependencies replaced with AppKit
- iOS AVPlayerViewController wrapper replaced by SwiftUI `VideoPlayer`
- Native macOS application target (`macosx`), not Mac Catalyst
- Desktop minimum/default window sizing
- `⌘R` reload command

## Note
This environment cannot run Xcode or link against the macOS SDK, so the project was parser-checked but the final `.app` must be built on a Mac with Xcode.
