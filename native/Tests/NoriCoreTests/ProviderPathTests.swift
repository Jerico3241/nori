import XCTest
@testable import NoriCore

/// Die Pfadbildung entscheidet, welche Seite abgerufen wird. Ein Fehler hier
/// führt zu 404 statt zu einem sichtbaren Absturz — schwer zu bemerken.
final class ProviderPathTests: XCTestCase {
    func testAniworldSeriesPath() {
        XCTAssertEqual(CatalogProvider.aniworld.seriesPath(slug: "one-piece"), "/anime/stream/one-piece")
        XCTAssertEqual(
            CatalogProvider.aniworld.seriesPath(slug: "one-piece", season: "3"),
            "/anime/stream/one-piece/staffel-3"
        )
        XCTAssertEqual(
            CatalogProvider.aniworld.seriesPath(slug: "one-piece", season: "filme"),
            "/anime/stream/one-piece/filme"
        )
    }

    func testSerienstreamSeriesPath() {
        XCTAssertEqual(CatalogProvider.serienstream.seriesPath(slug: "dexter"), "/serie/dexter")
        XCTAssertEqual(
            CatalogProvider.serienstream.seriesPath(slug: "dexter", season: "2"),
            "/serie/dexter/staffel-2"
        )
    }

    func testEpisodePaths() {
        XCTAssertEqual(
            CatalogProvider.aniworld.episodePath(slug: "demo", season: "2", episode: 5),
            "/anime/stream/demo/staffel-2/episode-5"
        )
        XCTAssertEqual(
            CatalogProvider.serienstream.episodePath(slug: "demo", season: "2", episode: 5),
            "/serie/demo/staffel-2/episode-5"
        )
        XCTAssertEqual(
            CatalogProvider.aniworld.episodePath(slug: "demo", season: "filme", episode: 3),
            "/anime/stream/demo/filme/film-3"
        )
    }

    func testEmptySeasonFallsBackToOne() {
        XCTAssertEqual(
            CatalogProvider.aniworld.episodePath(slug: "demo", season: "", episode: 1),
            "/anime/stream/demo/staffel-1/episode-1"
        )
    }

    /// Die Quelle wird an mehreren Stellen aus dem Pfad abgeleitet.
    func testProviderFromPath() {
        XCTAssertEqual(providerFromPath("/serie/dexter/staffel-1/episode-1"), .serienstream)
        XCTAssertEqual(providerFromPath("/anime/stream/demo/staffel-1/episode-1"), .aniworld)
    }

    /// Der Rückfall ist AniWorld — festgehalten, weil der Fortschritt nach
    /// `provider|episodePath` geschlüsselt ist: ändert sich diese Antwort,
    /// verlieren bestehende Einträge ihren Stand, statt bloß ein Etikett zu
    /// wechseln.
    func testProviderFromPathFallsBackToAniworld() {
        XCTAssertEqual(providerFromPath(""), .aniworld)
        XCTAssertEqual(providerFromPath("/etwas/ganz/anderes"), .aniworld)
    }

    /// Die Zuordnung hängt an `streamPrefix`, nicht an einer fest verdrahteten
    /// Zeichenkette. Damit trägt sie eine dritte Quelle von selbst mit.
    func testProviderFromPathUsesEveryStreamPrefix() {
        for provider in CatalogProvider.allCases {
            let path = provider.episodePath(slug: "demo", season: "1", episode: 1)
            XCTAssertEqual(providerFromPath(path), provider, "Pfad \(path)")
        }
    }

    func testNormalizeEpisodePath() {
        XCTAssertEqual(
            normalizeEpisodePath("https://aniworld.to/anime/stream/demo/staffel-1/episode-2/"),
            "/anime/stream/demo/staffel-1/episode-2"
        )
        XCTAssertEqual(normalizeEpisodePath("/serie/demo///"), "/serie/demo")
    }

    /// Dieselbe Serie bei beiden Quellen muss getrennt gespeichert bleiben.
    func testProgressKeySeparatesProviders() {
        let path = "/x/y"
        XCTAssertNotEqual(
            progressKey(path: path, provider: .aniworld),
            progressKey(path: path, provider: .serienstream)
        )
        XCTAssertEqual(progressKey(path: "/x/y/", provider: nil), "/x/y")
    }

    func testFormatClock() {
        XCTAssertEqual(formatClock(0), "0:00")
        XCTAssertEqual(formatClock(65), "1:05")
        XCTAssertEqual(formatClock(3661), "1:01:01")
        XCTAssertEqual(formatClock(-5), "0:00")
    }

    // MARK: - Coveradressen

    /// Warum es `guessedCoverPath` nicht mehr gibt.
    ///
    /// Die Adresse eines Covers lässt sich **nicht** aus dem Slug bilden:
    /// beide Quellen hängen einen Zufallsanteil an den Dateinamen. Dieser Test
    /// hält die tatsächlich ausgelieferten Namen fest — er schlägt fehl, wenn
    /// jemand die Ableitung wieder einführt, weil sie „naheliegend" aussieht.
    func testCoverFileNamesCarryAnUnguessableSuffix() {
        let aniworld = "/public/img/cover/black-clover-stream-cover-WWoAujz6fnp93s8iZ3F9iqqjO7WtXiIV_220x330.jpg"
        let serienstream = "/media/images/channel/desktop/black-mirror-7sqv7dhs"

        XCTAssertFalse(aniworld.hasSuffix("/black-clover.jpg"))
        XCTAssertFalse(serienstream.hasSuffix("/black-mirror"))
        // Und die Gegenrichtung trägt auch nicht: aus dem Dateinamen ist der
        // Slug nicht sauber zu gewinnen. Bei AniWorld scheitert es am
        // Unterstrich, bei Serienstream käme der Zufallsanteil mit.
        XCTAssertNil(HTML.slugFromPoster(aniworld))
        XCTAssertEqual(HTML.slugFromPoster(serienstream), "black-mirror-7sqv7dhs")
        XCTAssertNotEqual(HTML.slugFromPoster(serienstream), "black-mirror")
    }

    /// Serienstream liefert nach `format` aus und nennt in den eigenen Seiten
    /// `format=avif`. Nori erhält die tatsächlich gelieferte Adresse.
    func testCoverURLPreservesSerienstreamFormat() {
        let url = AniworldClient.coverURL(
            "/media/images/channel/desktop/black-mirror-7sqv7dhs?format=avif",
            provider: .serienstream
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://serienstream.to/media/images/channel/desktop/black-mirror-7sqv7dhs?format=avif"
        )
    }

    func testCoverURLDoesNotInventFormat() {
        let url = AniworldClient.coverURL(
            "/media/images/channel/desktop/black-mirror-7sqv7dhs",
            provider: .serienstream
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://serienstream.to/media/images/channel/desktop/black-mirror-7sqv7dhs"
        )
    }

    /// AniWorld liefert fertige Dateien — dort nichts anhängen.
    func testCoverURLLeavesAniworldAlone() {
        let path = "/public/img/cover/black-clover-stream-cover-WWoAujz6fnp93s8iZ3F9iqqjO7WtXiIV_220x330.jpg"
        XCTAssertEqual(
            AniworldClient.coverURL(path, provider: .aniworld)?.absoluteString,
            "https://aniworld.to" + path
        )
    }

    /// Eine bereits vollständige Adresse bleibt vollständig — sonst stünde der
    /// Host doppelt davor.
    func testCoverURLKeepsAbsoluteAddresses() {
        let absolute = "https://image.tmdb.org/t/p/w500/abc.jpg"
        XCTAssertEqual(
            AniworldClient.coverURL(absolute, provider: .aniworld)?.absoluteString,
            absolute
        )
    }

    // MARK: - Gemeinsame Bibliothek

    /// Beide Quellen können denselben Slug führen. Ohne die Quelle in der
    /// Kennung fiele in einer gemeinsamen Liste einer der beiden Titel weg.
    func testCatalogItemIdSeparatesProviders() {
        let anime = CatalogItem(slug: "gantz", title: "Gantz", alts: [], genres: [], provider: .aniworld)
        let serie = CatalogItem(slug: "gantz", title: "Gantz", alts: [], genres: [], provider: .serienstream)

        XCTAssertNotEqual(anime.id, serie.id)
        XCTAssertEqual(Set([anime, serie]).count, 2)
    }

    /// Ältere gespeicherte Kataloge kennen das Feld nicht.
    func testCatalogItemDecodesWithoutProvider() throws {
        let json = Data("""
        {"slug":"one-piece","title":"One Piece","alts":[],"genres":["Action"]}
        """.utf8)
        let item = try JSONDecoder().decode(CatalogItem.self, from: json)
        XCTAssertNil(item.provider)
        XCTAssertEqual(item.slug, "one-piece")
    }

    // MARK: - Bereich der Bibliothek

    func testScopeAllIncludesEverything() {
        XCTAssertTrue(LibraryScope.all.includes(.aniworld))
        XCTAssertTrue(LibraryScope.all.includes(.serienstream))
        XCTAssertTrue(LibraryScope.all.includes(nil))
        XCTAssertNil(LibraryScope.all.provider)
    }

    func testNamedScopeFiltersByProvider() {
        XCTAssertTrue(LibraryScope.aniworld.includes(.aniworld))
        XCTAssertFalse(LibraryScope.aniworld.includes(.serienstream))
        XCTAssertEqual(LibraryScope.aniworld.provider, .aniworld)
        XCTAssertEqual(LibraryScope.serienstream.provider, .serienstream)
    }

    /// Einträge aus einem älteren gespeicherten Stand tragen keine Quelle.
    /// Sie auszufiltern hieße, sie ganz verschwinden zu lassen.
    func testEntriesWithoutProviderSurviveEveryScope() {
        for scope in LibraryScope.allCases {
            XCTAssertTrue(scope.includes(nil), "\(scope.rawValue) hat einen Eintrag ohne Quelle verworfen")
        }
    }

    func testScopeLabelsAndHeadlines() {
        XCTAssertEqual(LibraryScope.all.label, "Alle")
        XCTAssertEqual(LibraryScope.aniworld.label, "Anime")
        XCTAssertEqual(LibraryScope.serienstream.label, "Serien")
        XCTAssertEqual(LibraryScope.all.headline, "Alle Titel")
        XCTAssertEqual(LibraryScope.serienstream.headline, "Alle Serien")
    }

    /// Der Kalender führt beide Quellen zusammen und entdoppelt über die
    /// Kennung — dieselbe Folge kann bei beiden Seiten am selben Tag laufen.
    func testAiringEntryIdSeparatesProviders() {
        func entry(_ provider: CatalogProvider?) -> AiringEntry {
            AiringEntry(
                airingAt: 0, episode: 3, season: "2", title: "Gantz", english: nil,
                slug: "gantz", languages: [], dayKey: "2026-09-14",
                dayLabel: "Montag, 14. September", coverPath: nil, provider: provider
            )
        }
        XCTAssertNotEqual(entry(.aniworld).id, entry(.serienstream).id)
        XCTAssertEqual(Set([entry(.aniworld), entry(.serienstream)]).count, 2)
    }
}

