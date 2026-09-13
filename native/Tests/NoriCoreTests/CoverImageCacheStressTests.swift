import XCTest
@testable import NoriCore
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

#if canImport(ImageIO)
/// Liefert Bilder für einen Host, den es nicht gibt, und zählt die Abrufe.
///
/// `.invalid` löst nie auf: fällt der Stub weg („offline"), kommt eine Anfrage
/// nur noch aus dem Plattenspeicher an — wie auf einem Gerät ohne Netz.
final class ImageStubProtocol: URLProtocol, @unchecked Sendable {
    static let host = "nori-cache-test.invalid"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _requests = 0
    nonisolated(unsafe) private static var _offline = false
    nonisolated(unsafe) private static var _body: (URL) -> Data = { _ in Data() }

    static var requests: Int { lock.lock(); defer { lock.unlock() }; return _requests }
    static var offline: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _offline }
        set { lock.lock(); _offline = newValue; lock.unlock() }
    }
    static func reset(body: @escaping (URL) -> Data) {
        lock.lock(); _requests = 0; _offline = false; _body = body; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host && !offline
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self._requests += 1
        let body = Self._body(url)
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": "image/png",
            "Content-Length": String(body.count),
            "Cache-Control": "public, max-age=86400",
        ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Belastung des Bild-Caches: über die Obergrenze, Neustart, offline,
/// beschädigte Dateien, Speicherwarnung, Leeren.
///
/// Mit kleiner Obergrenze statt 256 MB — geprüft wird der Mechanismus, nicht
/// die Zahl. Die Zahl selbst prüft `testProductionCapacityIs256MB`.
final class CoverImageCacheStressTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-image-stress-\(UUID().uuidString)", isDirectory: true)
        ImageStubProtocol.reset { url in Self.noisePNG(seed: url.lastPathComponent.hashValue, side: 160) }
    }

    override func tearDownWithError() throws {
        ImageStubProtocol.reset { _ in Data() }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Ein Bild aus Rauschen — lässt sich kaum komprimieren, die Größe ist
    /// damit planbar (Seite² × 4 Bytes, bei 160 px rund 100 KB).
    static func noisePNG(seed: Int, side: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        _ = seed
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        if let pixels = context.data?.bindMemory(to: UInt8.self, capacity: side * side * 4) {
            for i in 0 ..< side * side * 4 { pixels[i] = UInt8.random(in: 0 ... 255, using: &generator) }
        }
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func url(_ name: String) -> URL {
        URL(string: "https://\(ImageStubProtocol.host)/cover/\(name).png")!
    }

    private func loader(capacity: Int) -> CoverImageLoader {
        CoverImageLoader(directory: folder, diskCapacity: capacity, protocolClasses: [ImageStubProtocol.self])
    }

    /// Der Plattenspeicher schreibt verzögert. Kurz warten, bis er etwas meldet.
    private func settledDiskBytes(_ loader: CoverImageLoader, atLeast minimum: Int64 = 1) async -> Int64 {
        for _ in 0 ..< 40 {
            let bytes = await loader.diskBytes()
            if bytes >= minimum { return bytes }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await loader.diskBytes()
    }

    /// Was tatsächlich im Cache-Verzeichnis liegt, in Bytes.
    ///
    /// Nicht `URLCache.currentDiskUsage`: das ist eine Schätzung von CFNetwork
    /// und hinkt nach vielen Schreibvorgängen hinterher.
    private func bytesOnDisk() -> Int {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total = 0
        for case let file as URL in files {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += values?.fileSize ?? 0 }
        }
        return total
    }

    /// Wartet, bis sich das Verzeichnis eine Weile nicht mehr ändert.
    private func settledBytesOnDisk(timeout: TimeInterval = 20) async -> Int {
        let deadline = Date().addingTimeInterval(timeout)
        var last = -1
        var stable = 0
        while Date() < deadline {
            let now = bytesOnDisk()
            stable = now == last ? stable + 1 : 0
            last = now
            if stable >= 4 { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return last
    }

    func testProductionCapacityIs256MB() {
        XCTAssertEqual(CoverImageLoader.diskCapacity, 256 * 1024 * 1024)
    }

    /// Weit über die Obergrenze: jedes Bild kommt an, nichts stürzt ab, und
    /// das Verzeichnis wächst nicht mit — der Cache verdrängt.
    func testFillingFarBeyondTheLimitEvictsInsteadOfGrowing() async {
        // Gemessen: bei 1 MB und 4 MB Obergrenze legt URLCache überhaupt nichts
        // auf die Platte, das Verzeichnis bleibt leer — der Test wäre trivial
        // grün gewesen. Ab 8 MB wird geschrieben. Deshalb 16 MB und größere
        // Bilder (rund 260 KB, unter einem Zwanzigstel der Obergrenze, ab dem
        // URLCache eine Antwort gar nicht erst ablegt). In der App gilt 256 MB.
        ImageStubProtocol.reset { url in Self.noisePNG(seed: url.lastPathComponent.hashValue, side: 256) }
        let capacity = 16 * 1024 * 1024
        let loader = loader(capacity: capacity)
        var delivered = 0
        var written = 0
        for index in 0 ..< 250 {
            if let data = await loader.data(for: url("fill-\(index)"), referer: "https://aniworld.to/") {
                delivered += 1
                written += data.count
            }
        }
        XCTAssertEqual(delivered, 250)
        XCTAssertGreaterThan(written, capacity * 3, "Die Belastung muss die Obergrenze deutlich übersteigen")
        let onDisk = await settledBytesOnDisk()
        // Etwas muss liegen — sonst prüfte der Test keine Verdrängung.
        XCTAssertGreaterThan(onDisk, 1024 * 1024, "Verzeichnis: \(onDisk) B")
        // Nicht mehr als Obergrenze plus Datenbank und Verwaltungsreserve.
        XCTAssertLessThan(onDisk, capacity * 3 / 2, "Verzeichnis: \(onDisk) B bei \(written) B geschrieben")
    }

    /// Das Bild landet unverändert auf der Platte — die Voraussetzung dafür,
    /// dass es nach einem Neustart ohne Netz dasteht.
    ///
    /// Der Neustart selbst lässt sich in einem Testprozess nicht nachstellen:
    /// ein zweiter `URLCache` auf demselben Verzeichnis im selben Prozess sieht
    /// die Einträge des ersten nicht (gemessen: 30 s lang nicht, obwohl Datei
    /// und Datenbank geschrieben waren). Geprüft wird er deshalb in der App —
    /// laden, beenden, ohne Netz neu starten.
    func testCoverBytesArePersistedToDisk() async throws {
        let loader = loader(capacity: 8 * 1024 * 1024)
        let loaded = await loader.data(for: url("persist"), referer: "https://aniworld.to/")
        let original = try XCTUnwrap(loaded)
        _ = await settledBytesOnDisk()
        let bodies = folder.appendingPathComponent("fsCachedData", isDirectory: true)
        let stored = (try? FileManager.default.contentsOfDirectory(at: bodies, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(stored.contains { (try? Data(contentsOf: $0)) == original }, "Die Bytes des Covers liegen nicht auf der Platte")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Cache.db").path))
    }

    /// Beschädigte Dateien im Cache-Verzeichnis beim Start: kein Absturz, und
    /// geladen wird trotzdem.
    ///
    /// Die Beschädigung liegt vor, **bevor** ein Cache das Verzeichnis öffnet —
    /// so, wie sie nach einem Absturz, einem vollen Speicher oder einem
    /// abgebrochenen Schreiben beim nächsten Start vorgefunden wird.
    /// Absichtlich nicht nachgestellt: Dateien überschreiben, die der laufende
    /// Prozess gerade eingeblendet hat. Das beendet jeden SQLite-Nutzer mit
    /// SIGBUS (so im ersten Entwurf dieses Tests beobachtet, Absturz in
    /// `com.apple.CFNetwork.CacheDB-write`) und ist kein Zustand, den Nori
    /// selbst herbeiführen kann.
    func testCorruptedCacheFilesDoNotCrash() async throws {
        let garbage = { (size: Int) in Data((0 ..< size).map { _ in UInt8.random(in: 0 ... 255) }) }
        let bodies = folder.appendingPathComponent("fsCachedData", isDirectory: true)
        try FileManager.default.createDirectory(at: bodies, withIntermediateDirectories: true)
        try garbage(4096).write(to: folder.appendingPathComponent("Cache.db"))
        try garbage(1024).write(to: folder.appendingPathComponent("Cache.db-wal"))
        try garbage(512).write(to: folder.appendingPathComponent("Cache.db-shm"))
        for _ in 0 ..< 5 {
            try garbage(20_000).write(to: bodies.appendingPathComponent(UUID().uuidString))
        }

        let loader = loader(capacity: 8 * 1024 * 1024)
        for index in 0 ..< 10 {
            let data = await loader.data(for: url("corrupt-\(index)"), referer: "https://aniworld.to/")
            XCTAssertNotNil(data)
            let image = await loader.image(for: url("corrupt-\(index)"), referer: "https://aniworld.to/")
            XCTAssertNotNil(image)
        }
        await loader.purge()
        let again = await loader.data(for: url("after-purge"), referer: "https://aniworld.to/")
        XCTAssertNotNil(again)
    }

    /// Speicherwarnung: der Arbeitsspeicher wird frei, die Platte bleibt.
    func testMemoryWarningFreesMemoryButKeepsDisk() async {
        let loader = loader(capacity: 8 * 1024 * 1024)
        for index in 0 ..< 12 {
            _ = await loader.image(for: url("memory-\(index)"), referer: "https://aniworld.to/")
        }
        let before = await loader.memoryBytes()
        XCTAssertGreaterThan(before, 0)
        let disk = await settledDiskBytes(loader)

        await loader.trimMemory()

        let after = await loader.memoryBytes()
        XCTAssertEqual(after, 0)
        XCTAssertNil(DecodedImageCache.shared.image(for: url("memory-0")))
        let diskAfter = await loader.diskBytes()
        XCTAssertGreaterThanOrEqual(diskAfter, disk / 2)
        let reloaded = await loader.image(for: url("memory-0"), referer: "https://aniworld.to/")
        XCTAssertNotNil(reloaded)
    }

    /// Leeren: Platte und Arbeitsspeicher leer, danach lädt es wieder.
    func testPurgeEmptiesEverythingAndLoadingContinues() async {
        let loader = loader(capacity: 8 * 1024 * 1024)
        for index in 0 ..< 12 {
            _ = await loader.data(for: url("purge-\(index)"), referer: "https://aniworld.to/")
        }
        let disk = await settledDiskBytes(loader, atLeast: 100_000)
        XCTAssertGreaterThan(disk, 0)

        await loader.purge()

        let memory = await loader.memoryBytes()
        XCTAssertEqual(memory, 0)
        // Das Löschen auf der Platte läuft wie das Schreiben verzögert.
        var afterPurge = await loader.diskBytes()
        for _ in 0 ..< 50 where afterPurge >= disk {
            try? await Task.sleep(for: .milliseconds(200))
            afterPurge = await loader.diskBytes()
        }
        XCTAssertLessThan(afterPurge, disk)
        XCTAssertNil(DecodedImageCache.shared.image(for: url("purge-0")))
        let again = await loader.data(for: url("purge-0"), referer: "https://aniworld.to/")
        XCTAssertNotNil(again)
    }

    /// Viele Kacheln fragen gleichzeitig nach demselben Cover: ein Abruf.
    func testConcurrentRequestsForOneCoverShareOneDownload() async {
        let loader = loader(capacity: 8 * 1024 * 1024)
        let target = url("shared")
        await withTaskGroup(of: Data?.self) { group in
            for _ in 0 ..< 25 {
                group.addTask { await loader.data(for: target, referer: "https://aniworld.to/") }
            }
            var hits = 0
            for await result in group where result != nil { hits += 1 }
            XCTAssertEqual(hits, 25)
        }
        XCTAssertEqual(ImageStubProtocol.requests, 1)
    }
}
#endif
