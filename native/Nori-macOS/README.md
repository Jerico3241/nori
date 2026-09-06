# Nori macOS 1.12.2

Native macOS build of the Nori SwiftUI client. Changes per release: [../../CHANGELOG.md](../../CHANGELOG.md)

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

## macOS interface

The macOS target no longer mirrors the iOS layout. It uses desktop conventions:

- `NavigationSplitView` with a source list sidebar (Start, Katalog, Kalender, Merkliste) instead of an iOS tab bar
- Source switch (Anime / Serien) lives once at the bottom of the sidebar as a segmented picker, instead of a drag-operated capsule repeated in every toolbar
- Preferences live in the standard `Settings` scene (`⌘,`) with tab panes, not in a navigation tab
- Playback runs in its own window (own title bar, green-button full screen, `⌘W`) instead of a modal sheet; hoster, language, speed and episode skip sit in the window toolbar so they no longer cover the AVKit transport controls
- Explicit refresh buttons in the toolbar plus `⌘R`, because pull-to-refresh does not exist on macOS
- Adaptive color palette: the app follows the system appearance instead of forcing dark mode
- Hover states on posters and rows, right-click context menus, tooltips (`help`)
- Keyboard shortcuts: `⌘1`–`⌘4` for the sidebar sections, `⌘R` refresh, `⌘,` settings, `Return` plays the highlighted episode
- Catalog can be shown as list or poster grid (choice is remembered)
- Native list styling (`inset`, alternating rows) instead of iOS row backgrounds
- Display sleep is blocked while a stream is playing
- Window minimum reduced to 720 × 460 so the app fits smaller displays

## Other macOS adaptations
- UIKit dependencies replaced with AppKit
- iOS AVPlayerViewController wrapper replaced by SwiftUI `VideoPlayer`
- Native macOS application target (`macosx`), not Mac Catalyst
- Complete classic macOS AppIcon asset set (16–1024 px)

## Current test status
The macOS interface was rebuilt around desktop conventions (see above). The rewrite targets macOS 14 APIs only and has **not** been compiled yet — it still needs one `⌘B` in Xcode on a real Mac before it can be considered verified.

## Note
The iCloud key-value sync implementation still requires the corresponding Xcode capability/entitlement before it can be considered production-ready.

