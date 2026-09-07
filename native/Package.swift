// swift-tools-version: 5.9
import PackageDescription

// Plattformunabhängiger Kern von Nori. Die Apple-Apps referenzieren dieselben
// Dateien direkt, während SwiftPM sie für Tests und den Android-Cross-Build als
// echtes NoriCore-Target baut. Dadurch existiert jede Kernimplementierung nur
// noch einmal im Repository.
let package = Package(
    name: "NoriCore",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "NoriCore",
            dependencies: ["SwiftSoup"],
            path: "NoriCore/Sources/NoriCore"
        ),
        .testTarget(
            name: "NoriCoreTests",
            dependencies: ["NoriCore"],
            path: "Tests/NoriCoreTests"
        ),
    ]
)
