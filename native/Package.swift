// swift-tools-version: 5.9
import PackageDescription

// Testpaket für die plattformunabhängigen Kernregeln.
//
// Es bindet `Models.swift` aus dem macOS-Target direkt ein, statt sie zu
// kopieren — die Datei ist zwischen iOS und macOS byte-gleich (siehe
// .claude/skills/apple-parity), also prüft der Test beide Targets zugleich.
// Ein XCTest-Target in den handgeschriebenen Xcode-Projekten wäre ohne Xcode
// nicht verlässlich zu pflegen; ein Paket lässt sich mit `swift test` überall
// ausführen, wo eine Swift-Toolchain vorhanden ist.
let package = Package(
    name: "NoriCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "NoriCore",
            path: "Nori-macOS/Nori",
            // Alles außer Models.swift ausschließen, sonst meldet SwiftPM die
            // App-Dateien als unbehandelte Ressourcen. Kommt eine Datei dazu,
            // gibt es eine Warnung — kein stiller Fehlschlag.
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "AniworldClient.swift",
                "CalendarView.swift",
                "CatalogView.swift",
                "CategoriesView.swift",
                "HTML.swift",
                "HomeView.swift",
                "HosterResolver.swift",
                "LibraryStore.swift",
                "NoriApp.swift",
                "PlayerScreen.swift",
                "SeriesView.swift",
                "SettingsView.swift",
                "Theme.swift",
                "WatchlistView.swift",
            ],
            sources: ["Models.swift"]
        ),
        .testTarget(
            name: "NoriCoreTests",
            dependencies: ["NoriCore"],
            path: "Tests/NoriCoreTests"
        ),
    ]
)
