import XCTest
@testable import NoriCore

/// Revisionen und gebündeltes Schreiben des `LibraryStore`.
///
/// Zwei Fehlerklassen, die sich in keiner Ansicht direkt zeigen:
///
/// - **Anzahl statt Revision.** Die Ansichten erkannten Änderungen an
///   `favorites.count` und `progress.count`. Wird ein Titel entfernt und ein
///   anderer gemerkt, bleibt die Anzahl gleich — die Merkliste stand veraltet
///   da. Wird eine angefangene Folge zu Ende gesehen, ändert sich die Anzahl
///   gar nicht, und „Weiterschauen" zeigte sie weiter.
/// - **Schreiben im Takt des Players.** Jede Sicherung alle fünf Sekunden
///   schrieb die ganze Bibliothek auf die Platte.
final class LibraryRevisionTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("nori-revision-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.lock(); value += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func progress(
        _ slug: String = "frieren",
        episode: Int = 1,
        position: Double,
        duration: Double = 1400,
        lang: String? = "DE",
        completed: Bool? = nil
    ) -> WatchProgress {
        WatchProgress(
            slug: slug, title: slug, season: "1", episode: episode,
            episodePath: "/anime/stream/\(slug)/staffel-1/episode-\(episode)",
            germanTitle: "", englishTitle: "",
            positionSec: position, durationSec: duration,
            updatedAt: Date().timeIntervalSince1970 * 1000,
            lang: lang, completed: completed, provider: .aniworld
        )
    }

    // MARK: - Merkliste

    /// Derselbe Umfang, anderer Inhalt: die Revision muss es merken.
    func testFavoritesRevisionChangesWhenCountStaysTheSame() {
        let store = LibraryStore(directory: directory)
        store.toggleFavorite("dexter", title: "Dexter")
        let before = store.favoritesRevision
        let count = store.favorites.count

        store.removeFavorite("dexter")
        store.toggleFavorite("dark", title: "Dark")

        XCTAssertEqual(store.favorites.count, count)
        XCTAssertGreaterThan(store.favoritesRevision, before)
    }

    func testRecentsRevisionCountsEveryVisit() {
        let store = LibraryStore(directory: directory)
        store.remember(slug: "dark", title: "Dark")
        let before = store.recentsRevision
        // Derselbe Titel noch einmal: gleiche Anzahl, andere Reihenfolge.
        store.remember(slug: "monster", title: "Monster")
        store.remember(slug: "dark", title: "Dark")
        XCTAssertEqual(store.recentsRevision, before + 2)
        XCTAssertEqual(store.recents.first?.slug, "dark")
    }

    // MARK: - Fortschritt

    /// Eine abgeschlossene Folge ändert „Weiterschauen", aber nicht die Anzahl.
    func testCompletingAnEpisodeBumpsWatchRevisionWithoutChangingTheCount() {
        let store = LibraryStore(directory: directory)
        store.upsert(progress(position: 400))
        let count = store.progress.count
        let before = store.watchRevision

        store.upsert(progress(position: 1390))

        XCTAssertEqual(store.progress.count, count)
        XCTAssertGreaterThan(store.watchRevision, before)
        XCTAssertTrue(store.continueWatching().isEmpty)
    }

    /// Der Fünf-Sekunden-Takt: jede Sicherung zählt für die Position, keine
    /// für die Listen — bis die Wiedergabe endet.
    func testPlaybackTicksOnlyBumpProgressRevisionUntilFlush() {
        let store = LibraryStore(directory: directory)
        store.upsert(progress(position: 10))
        let watch = store.watchRevision
        let position = store.progressRevision

        store.upsert(progress(position: 15))
        store.upsert(progress(position: 20))
        store.upsert(progress(position: 25))

        XCTAssertEqual(store.progressRevision, position + 3)
        XCTAssertEqual(store.watchRevision, watch, "Ein Takt darf die Startseite nicht neu rechnen lassen")

        store.flush()
        XCTAssertEqual(store.watchRevision, watch + 1, "Das Ende der Wiedergabe schließt die Takte ab")
        store.flush()
        XCTAssertEqual(store.watchRevision, watch + 1, "Ein zweites flush ohne neue Takte ändert nichts")
    }

    /// Die erste Sicherung einer neuen Wiedergabe ist kein Takt, auch wenn es
    /// die Folge schon gibt: sie rückt in „Weiterschauen" nach vorn.
    func testFirstSaveOfAnotherEpisodeIsNotATick() {
        let store = LibraryStore(directory: directory)
        store.upsert(progress("frieren", position: 300))
        store.upsert(progress("dark", position: 300))
        let before = store.watchRevision

        store.upsert(progress("frieren", position: 310))

        XCTAssertEqual(store.watchRevision, before + 1)
        XCTAssertEqual(store.continueWatching().first?.slug, "frieren")
    }

    func testLanguageSwitchIsNotATick() {
        let store = LibraryStore(directory: directory)
        store.upsert(progress(position: 100, lang: "DE"))
        store.upsert(progress(position: 105, lang: "DE"))
        let before = store.watchRevision
        store.upsert(progress(position: 110, lang: "GerSub"))
        XCTAssertEqual(store.watchRevision, before + 1)
    }

    // MARK: - Schreiben

    /// Ein Takt steht sofort im Speicher, auf der Platte erst nach `flush` —
    /// eine neue Folge dagegen sofort.
    func testTicksAreWrittenOnFlushNotImmediately() {
        let store = LibraryStore(directory: directory)
        store.upsert(progress(position: 100))
        store.upsert(progress(position: 105))

        XCTAssertEqual(store.progress(slug: "frieren", season: "1", episode: 1)?.positionSec, 105)
        let onDisk = LibraryStore(directory: directory)
        XCTAssertEqual(
            onDisk.progress(slug: "frieren", season: "1", episode: 1)?.positionSec, 100,
            "Die neue Folge stand sofort auf der Platte, der Takt noch nicht"
        )

        store.flush()
        let afterFlush = LibraryStore(directory: directory)
        XCTAssertEqual(afterFlush.progress(slug: "frieren", season: "1", episode: 1)?.positionSec, 105)
    }

    /// Das geplante Schreiben kommt auch ohne `flush` — spätestens nach der
    /// eingestellten Zeit.
    func testDeferredWriteHappensWithoutFlush() {
        let store = LibraryStore(directory: directory, deferredWriteDelay: 0.2)
        store.upsert(progress(position: 100))
        store.upsert(progress(position: 140))

        let written = expectation(description: "geschrieben")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            written.fulfill()
        }
        wait(for: [written], timeout: 5)

        XCTAssertEqual(
            LibraryStore(directory: directory).progress(slug: "frieren", season: "1", episode: 1)?.positionSec,
            140
        )
    }

    /// Eine ganze Staffel ist eine Änderung, nicht vierundzwanzig.
    func testBatchUpsertReportsOneChange() {
        let store = LibraryStore(directory: directory)
        let changes = Counter()
        store.onChange = { changes.increment() }

        store.upsert(contentsOf: (1 ... 24).map { progress(episode: $0, position: 1400, completed: true) })

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(store.progress.count, 24)
        XCTAssertEqual(LibraryStore(directory: directory).progress.count, 24)
    }

    // MARK: - Einstellungen

    /// Derselbe Wert ist keine Änderung: keine Marke, keine Meldung, kein Upload.
    func testAssigningTheSameValueIsNotAChange() throws {
        let store = LibraryStore(directory: directory)
        store.hosterPref = "Vidoza"
        let stamp = try XCTUnwrap(store.snapshot().sync?.preferences?["hosterPref"]?.updatedAt)
        let changes = Counter()
        store.onChange = { changes.increment() }

        store.hosterPref = "Vidoza"
        store.langPref = store.langPref
        store.scope = store.scope

        XCTAssertEqual(changes.count, 0)
        XCTAssertEqual(store.snapshot().sync?.preferences?["hosterPref"]?.updatedAt, stamp)

        store.hosterPref = "VOE"
        XCTAssertEqual(changes.count, 1)
    }
}
