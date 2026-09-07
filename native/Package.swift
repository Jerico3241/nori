// swift-tools-version: 5.9
import PackageDescription

// Plattformunabhängiger Kern von Nori. Die Apple-Apps referenzieren dieselben
// Dateien direkt, während SwiftPM sie für Tests und den Android-Cross-Build als
// echtes NoriCore-Target baut. Dadurch existiert jede Kernimplementierung nur
// noch einmal im Repository.
//
// Für Android kommt ein zweites Produkt dazu: `NoriAndroid` ist dieselbe
// Kernlogik als dynamische Bibliothek, gebündelt mit der JNI-Hülle. Der
// Gradle-Build kopiert die fertige `libNoriAndroid.so` nach `jniLibs` und
// braucht dafür weder NDK noch CMake.
let package = Package(
    name: "NoriCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NoriCore", targets: ["NoriCore"]),
        // Nur für Android gedacht. Auf Apple lässt sich das Produkt zwar
        // bauen, die JNI-Hülle ist dort aber leer — `nori_jni.c` steht
        // vollständig in `#if defined(__ANDROID__)`.
        .library(name: "NoriAndroid", type: .dynamic, targets: ["NoriCore", "NoriJNI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "NoriCore",
            dependencies: ["SwiftSoup"],
            path: "NoriCore/Sources/NoriCore"
        ),
        .target(
            name: "NoriJNI",
            path: "Nori-Android/jni",
            exclude: [],
            sources: ["nori_jni.c"]
        ),
        .testTarget(
            name: "NoriCoreTests",
            dependencies: ["NoriCore"],
            path: "Tests/NoriCoreTests"
        ),
    ]
)
