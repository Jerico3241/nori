import XCTest
@testable import NoriCore

#if DEBUG
/// Welche Anfragen die Debug-Netzsimulation stört — und welche nicht.
///
/// Die Regel ist rein; geprüft wird, dass jeder Modus genau die Hosts trifft,
/// die er verspricht. Ein „nur AniWorld", das nebenbei TMDB abschneidet, würde
/// beim Nachstellen einen Fehler zeigen, den es in Wirklichkeit nicht gibt.
final class NetworkSimulationTests: XCTestCase {

    func testOfflineFailsEverything() {
        for host in ["aniworld.to", "api.themoviedb.org", "www.googleapis.com", "voe.sx"] {
            XCTAssertEqual(NoriNetworkSimulation.offline.effect(host: host), .fail(.notConnectedToInternet), host)
        }
    }

    func testSlowDelaysButDelivers() {
        XCTAssertEqual(NoriNetworkSimulation.slow.effect(host: "aniworld.to"), .delay(4))
    }

    func testTMDBTimeoutOnlyHitsTMDB() {
        let mode = NoriNetworkSimulation.tmdbTimeout
        XCTAssertEqual(mode.effect(host: "api.themoviedb.org"), .hang(12))
        XCTAssertEqual(mode.effect(host: "image.tmdb.org"), .hang(12))
        XCTAssertEqual(mode.effect(host: "aniworld.to"), .pass)
        XCTAssertEqual(mode.effect(host: "serienstream.to"), .pass)
    }

    func testTMDBSlowDelaysOnlyTMDB() {
        let mode = NoriNetworkSimulation.tmdbSlow
        XCTAssertEqual(mode.effect(host: "api.themoviedb.org"), .delay(8))
        XCTAssertEqual(mode.effect(host: "aniworld.to"), .pass)
    }

    func testSingleProviderTimeoutsHitOnlyTheirProvider() {
        XCTAssertEqual(NoriNetworkSimulation.aniworldTimeout.effect(host: "aniworld.to"), .hang(20))
        XCTAssertEqual(NoriNetworkSimulation.aniworldTimeout.effect(host: "serienstream.to"), .pass)
        XCTAssertEqual(NoriNetworkSimulation.aniworldTimeout.effect(host: "api.themoviedb.org"), .pass)
        XCTAssertEqual(NoriNetworkSimulation.serienstreamTimeout.effect(host: "s.to"), .hang(20))
        XCTAssertEqual(NoriNetworkSimulation.serienstreamTimeout.effect(host: "aniworld.to"), .pass)
    }

    func testProviderTimeoutLeavesTMDBAndGoogleAlone() {
        let mode = NoriNetworkSimulation.providerTimeout
        XCTAssertEqual(mode.effect(host: "aniworld.to"), .hang(20))
        XCTAssertEqual(mode.effect(host: "s.to"), .hang(20))
        XCTAssertEqual(mode.effect(host: "api.themoviedb.org"), .pass)
        XCTAssertEqual(mode.effect(host: "oauth2.googleapis.com"), .pass)
    }

    func testSingleProviderModesAreMirrorImages() {
        XCTAssertEqual(NoriNetworkSimulation.onlyAniworld.effect(host: "serienstream.to"), .fail(.cannotConnectToHost))
        XCTAssertEqual(NoriNetworkSimulation.onlyAniworld.effect(host: "aniworld.to"), .pass)
        XCTAssertEqual(NoriNetworkSimulation.onlySerienstream.effect(host: "aniworld.to"), .fail(.cannotConnectToHost))
        XCTAssertEqual(NoriNetworkSimulation.onlySerienstream.effect(host: "serienstream.to"), .pass)
    }

    /// Kein Treffer über ähnliche Namen: `notaniworld.to` ist nicht AniWorld.
    func testDomainsMatchOnLabelBoundaries() {
        XCTAssertEqual(NoriNetworkSimulation.onlySerienstream.effect(host: "notaniworld.to"), .pass)
        XCTAssertEqual(NoriNetworkSimulation.onlySerienstream.effect(host: "cdn.aniworld.to"), .fail(.cannotConnectToHost))
    }

    func testDriveOfflineOnlyHitsGoogle() {
        let mode = NoriNetworkSimulation.driveOffline
        XCTAssertEqual(mode.effect(host: "www.googleapis.com"), .fail(.notConnectedToInternet))
        XCTAssertEqual(mode.effect(host: "oauth2.googleapis.com"), .fail(.notConnectedToInternet))
        XCTAssertEqual(mode.effect(host: "aniworld.to"), .pass)
    }

    // MARK: - Durch eine echte Sitzung

    private func session(cache: URLCache) -> URLSession {
        // `.default` wie `CoverImageLoader`: eine flüchtige Sitzung räumt
        // ihren Plattenspeicher beim Start selbst weg.
        let config = URLSessionConfiguration.default
        config.urlCache = cache
        config.requestCachePolicy = .returnCacheDataElseLoad
        NoriNetworkSimulation.configure(config)
        return URLSession(configuration: config)
    }

    /// Offline kommt, was im Zwischenspeicher liegt — wie auf einem echten
    /// Gerät. Vorher blieben unter der Simulation alle Cover leer.
    func testOfflineStillServesCachedResponses() async throws {
        NoriNetworkSimulation.forced = .offline
        defer { NoriNetworkSimulation.forced = nil }

        // Nur im Arbeitsspeicher: der Weg durch die Simulation ist derselbe,
        // und ein Plattenspeicher im Testordner räumt sich beim Anlegen
        // einer Sitzung selbst weg.
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        let url = URL(string: "https://image.tmdb.org/t/p/w342/test-\(UUID().uuidString).jpg")!
        let body = Data("bild".utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/jpeg"])!
        cache.storeCachedResponse(CachedURLResponse(response: response, data: body), for: URLRequest(url: url))

        let (data, _) = try await session(cache: cache).data(from: url)
        XCTAssertEqual(data, body)
    }

    func testOfflineFailsWithoutCachedResponse() async {
        NoriNetworkSimulation.forced = .offline
        defer { NoriNetworkSimulation.forced = nil }

        // Nur im Arbeitsspeicher: der Weg durch die Simulation ist derselbe,
        // und ein Plattenspeicher im Testordner räumt sich beim Anlegen
        // einer Sitzung selbst weg.
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0)
        let url = URL(string: "https://aniworld.to/animes-\(UUID().uuidString)")!

        do {
            _ = try await session(cache: cache).data(from: url)
            XCTFail("Ohne Zwischenspeicher darf offline nichts ankommen")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }

    func testModesParseFromLaunchArgumentSpelling() {
        XCTAssertEqual(NoriNetworkSimulation(rawValue: "tmdb-timeout"), .tmdbTimeout)
        XCTAssertEqual(NoriNetworkSimulation(rawValue: "only-serienstream"), .onlySerienstream)
        XCTAssertEqual(NoriNetworkSimulation(rawValue: "tmdb-slow"), .tmdbSlow)
        XCTAssertEqual(NoriNetworkSimulation(rawValue: "aniworld-timeout"), .aniworldTimeout)
        XCTAssertEqual(NoriNetworkSimulation(rawValue: "serienstream-timeout"), .serienstreamTimeout)
        XCTAssertNil(NoriNetworkSimulation(rawValue: "irgendwas"))
    }
}
#endif
