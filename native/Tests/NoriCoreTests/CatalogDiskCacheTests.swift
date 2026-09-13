import XCTest
@testable import NoriCore

/// Der Katalog-Rückfall auf der Platte.
///
/// Ohne Netz soll nach einem Neustart der Stand von gestern dastehen statt
/// einer leeren Seite — aber nie ein kaputter oder halber.
final class CatalogDiskCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-catalog-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func result(count: Int, provider: CatalogProvider = .aniworld) -> CatalogResult {
        let items = (0 ..< count).map {
            CatalogItem(slug: "titel-\($0)", title: "Titel \($0)", alts: [], genres: ["Drama"], provider: provider)
        }
        return CatalogResult(items: items, source: "live", fetchedAt: 1)
    }

    func testRoundTripMarksTheResultAsCached() throws {
        let cache = CatalogDiskCache(directory: directory)
        cache.save(result(count: 25), provider: .aniworld)

        let loaded = try XCTUnwrap(cache.load(provider: .aniworld))
        XCTAssertEqual(loaded.items.count, 25)
        XCTAssertEqual(loaded.source, "cache")
        XCTAssertEqual(loaded.items.first?.provider, .aniworld)
    }

    func testProvidersAreStoredSeparately() {
        let cache = CatalogDiskCache(directory: directory)
        cache.save(result(count: 30, provider: .serienstream), provider: .serienstream)

        XCTAssertNil(cache.load(provider: .aniworld))
        XCTAssertEqual(cache.load(provider: .serienstream)?.items.count, 30)
    }

    /// Ein halber Katalog — Schutzseite, geändertes Markup — wird nicht
    /// abgelegt und überschreibt keinen guten.
    func testIncompleteCatalogIsNotStored() {
        let cache = CatalogDiskCache(directory: directory)
        cache.save(result(count: 25), provider: .aniworld)
        cache.save(result(count: 3), provider: .aniworld)

        XCTAssertEqual(cache.load(provider: .aniworld)?.items.count, 25)
    }

    func testCorruptedFileYieldsNothing() throws {
        let cache = CatalogDiskCache(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"items\": [ kaputt".utf8).write(to: directory.appendingPathComponent("aniworld.json"))

        XCTAssertNil(cache.load(provider: .aniworld))
    }

    func testMissingDirectoryYieldsNothing() {
        XCTAssertNil(CatalogDiskCache(directory: nil).load(provider: .aniworld))
        XCTAssertNil(CatalogDiskCache(directory: directory).load(provider: .aniworld))
    }
}
