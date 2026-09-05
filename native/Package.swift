// swift-tools-version: 5.9
import PackageDescription

// Testpaket für die plattformunabhängigen Kernregeln.
//
// Es bindet `Models.swift`, `HTML.swift`, `AniworldClient.swift` und
// `HosterResolver.swift` aus dem macOS-Target direkt ein, statt sie zu
// kopieren — alle vier sind zwischen iOS und macOS byte-gleich
// (siehe .claude/skills/apple-parity), also prüft der Test beide Targets
// zugleich. Ein XCTest-Target in den handgeschriebenen Xcode-Projekten wäre
// ohne Xcode nicht verlässlich zu pflegen; ein Paket lässt sich mit
// `swift test` überall ausführen, wo eine Swift-Toolchain vorhanden ist.
//
// SwiftSoup ist auf dieselbe Spanne gepinnt wie in beiden Xcode-Projekten
// (2.7.0, up to next major). Läuft das auseinander, parst der Test etwas
// anderes als die App.
let package = Package(
    name: "NoriCore",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "NoriCore",
            dependencies: ["SwiftSoup"],
            path: "Nori-macOS/Nori",
            // Alles außer den geprüften Dateien ausschließen, sonst meldet
            // SwiftPM die App-Dateien als unbehandelte Ressourcen. Kommt eine
            // Datei dazu, gibt es eine Warnung — kein stiller Fehlschlag.
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "CalendarView.swift",
                "CatalogView.swift",
                "CategoriesView.swift",
                "HomeView.swift",
                "LibraryStore.swift",
                "NoriApp.swift",
                "PlayerScreen.swift",
                "SeriesView.swift",
                "SettingsView.swift",
                "Theme.swift",
                "WatchlistView.swift",
            ],
            sources: ["Models.swift", "HTML.swift", "AniworldClient.swift", "HosterResolver.swift"]
        ),
        .testTarget(
            name: "NoriCoreTests",
            dependencies: ["NoriCore"],
            path: "Tests/NoriCoreTests"
        ),
    ]
)
