// swift-tools-version: 5.9
import PackageDescription

// Testpaket für die plattformunabhängigen Kernregeln.
//
// Es bindet die fünf byte-gleichen Dateien aus dem macOS-Target direkt ein,
// statt sie zu kopieren — `Models`, `HTML`, `AniworldClient`, `HosterResolver`
// und `LibraryStore` sind zwischen iOS und macOS identisch
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
    // macOS 14, nicht 13: `LibraryStore` ist `@Observable`, und das
    // Observation-Framework gibt es erst ab macOS 14. Der Testlauf verwendet
    // ohnehin macos-14.
    platforms: [.macOS(.v14)],
    // Ohne ein Produkt linkt SwiftPM nichts Bleibendes: ein `target` allein
    // wird übersetzt und wieder verworfen. Für Android braucht die App den
    // Kern aber als echte `libNoriCore.so`, die das APK mitbringt und Kotlin
    // über `System.loadLibrary` öffnet — deshalb `.dynamic` und nicht die
    // Vorgabe (statisch).
    //
    // Auf Apple ändert das nichts: die beiden Xcode-Projekte übersetzen die
    // Dateien selbst und lesen dieses Paket gar nicht. Es dient dem Testlauf
    // und dem Android-Durchbau.
    products: [
        .library(name: "NoriCore", type: .dynamic, targets: ["NoriCore"]),
        // Was das APK lädt: Kern **und** Brücke in einer Bibliothek. Zwei
        // getrennte `.so` wären zwei Ladevorgänge und ein Symbolpfad mehr,
        // der schiefgehen kann.
        .library(name: "NoriAndroid", type: .dynamic, targets: ["NoriBridge"]),
    ],
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
                "NoriApp.swift",
                "PlayerScreen.swift",
                "SeriesView.swift",
                "SettingsView.swift",
                "Theme.swift",
                "WatchlistView.swift",
            ],
            sources: ["Models.swift", "HTML.swift", "AniworldClient.swift", "HosterResolver.swift", "LibraryStore.swift"]
        ),
        // Die C-ABI-Brücke für Android. Reines Swift und Foundation — kein
        // `jni.h`, keine NDK-Abhängigkeit —, damit `swift test` auf dem Mac
        // davon unberührt bleibt. Den eigentlichen JNI-Shim baut Gradle.
        .target(
            name: "NoriBridge",
            dependencies: ["NoriCore"],
            path: "NoriBridge"
        ),
        .testTarget(
            name: "NoriCoreTests",
            dependencies: ["NoriCore"],
            path: "Tests/NoriCoreTests"
        ),
    ]
)
