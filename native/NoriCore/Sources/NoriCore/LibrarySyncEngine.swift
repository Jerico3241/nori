import Foundation
import Observation

// Der Ablauf eines Abgleichs. Was wann geholt, gerechnet und geschrieben wird.
//
// Die Aufteilung ist Absicht:
//
//     LibraryStore        kennt die Daten
//     LibrarySyncEngine   kennt den Ablauf
//     LibrarySnapshotStore kennt die Ablage
//     GoogleDriveClient   kennt HTTP
//     GoogleAuthorization kennt OAuth
//
// Keine OAuth-Logik im Store, kein Drive-HTTP in einer View. Wer das
// vermischt, hat am Ende fünf Stellen, an denen ein Token erneuert wird, und
// an vieren davon falsch.

/// Was der Abgleich gerade tut. Gleiches Modell auf allen Plattformen.
enum LibrarySyncStatus: Equatable {
    case disconnected
    case authorizing
    case idle
    case syncing
    /// Kein Netz. Kein Fehler, sondern ein Zustand — die Änderungen liegen
    /// lokal und gehen nicht verloren.
    case offline
    case error(String)
    /// In der Cloud liegt ein Stand, den diese App-Version noch nicht kennt.
    /// Hochladen wäre Datenverlust; also wird nicht hochgeladen.
    case unsupportedRemoteVersion
}

/// Eine Gerätedatei in der Ablage.
struct RemoteSnapshotRef: Equatable {
    var id: String
    var deviceId: String?
    var modifiedTime: String
    var size: Int
}

/// Wohin die Gerätestände gelegt werden.
///
/// Getrennt von `LibrarySyncProvider`: der alte Weg legt *eine* Datei ab und
/// bleibt für einfache Ablagen richtig. Dieser hier kennt viele Dateien, je
/// eine pro Gerät, und genau das braucht ein Abgleich über mehr als zwei
/// Geräte.
protocol LibrarySnapshotStore: AnyObject, Sendable {
    /// Für die Oberfläche, etwa „Google Drive".
    var name: String { get }
    func list() async throws -> [RemoteSnapshotRef]
    func download(_ ref: RemoteSnapshotRef) async throws -> Data
    /// Legt an oder überschreibt.
    ///
    /// Zurück kommt die vollständige Referenz und nicht nur die Kennung: mit
    /// dem Änderungsstempel kann der Aufrufer den eben geschriebenen Stand
    /// merken, statt ihn beim nächsten Abgleich zurückzuholen, um
    /// festzustellen, dass er von ihm selbst stammt.
    func upload(_ data: Data, deviceId: String, fileId: String?) async throws -> RemoteSnapshotRef
}

/// Wo sich die Engine merkt, was nicht in die Bibliothek gehört.
///
/// Die eigene Drive-Dateikennung zum Beispiel: sie gehört zu einem
/// Google-Konto, nicht zu den Daten. Stünde sie in `library.json`, wanderte sie
/// beim nächsten Abgleich auf alle anderen Geräte — und die schrieben dann in
/// *diese* Datei.
protocol SyncBookkeeping: AnyObject {
    func syncValue(forKey key: String) -> String?
    func setSyncValue(_ value: String?, forKey key: String)
}

/// `@Observable`, weil die Einstellungen den Zustand zeigen. Ohne das müsste
/// die Oberfläche pollen, um einen laufenden Abgleich von einem fertigen zu
/// unterscheiden.
@MainActor
@Observable
final class LibrarySyncEngine {
    /// Bündelung normaler Änderungen: Merkliste, Einstellungen, Verlauf.
    static let debounce: Double = 4
    /// Während durchgehender Wiedergabe höchstens alle 25 Sekunden.
    ///
    /// Der Fortschritt wird lokal im Sekundentakt geschrieben — das muss er
    /// auch, sonst fehlt nach einem Absturz die letzte Minute. In die Cloud
    /// gehört er deshalb noch lange nicht im Sekundentakt.
    static let playbackInterval: Double = 25
    /// Wie oft im Vordergrund nach fremden Änderungen gesehen wird.
    static let foregroundPoll: Double = 30

    private static let fileIdKey = "nori.sync.driveFileId"
    private static let accountKey = "nori.sync.accountId"

    private let store: LibraryStore
    private let bookkeeping: SyncBookkeeping
    private let clock: @Sendable () -> Double

    private(set) var status: LibrarySyncStatus = .disconnected
    private(set) var lastSuccessfulSync: Double?
    private(set) var lastError: String?
    /// Ein einzelner Fremdstand war unlesbar. Kein Grund abzubrechen, aber
    /// auch nichts, das stillschweigend verschwinden sollte.
    private(set) var lastWarning: String?
    private(set) var hasPendingChanges = false

    private var snapshotStore: LibrarySnapshotStore?
    private var running = false
    private var pending = false
    private var debounceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastUploadAt: Double = 0
    /// Was schon einmal heruntergeladen wurde, nach Dateikennung.
    /// Unveränderte Dateien werden nicht erneut geholt.
    private var cache: [String: (modifiedTime: String, data: LibraryData)] = [:]

    init(
        store: LibraryStore,
        bookkeeping: SyncBookkeeping,
        clock: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 * 1000 }
    ) {
        self.store = store
        self.bookkeeping = bookkeeping
        self.clock = clock
    }

    /// Nur für die Anmeldung, die außerhalb der Engine läuft — sonst setzt den
    /// Zustand ausschließlich `run()`.
    func setStatus(_ next: LibrarySyncStatus) { status = next }

    var providerName: String? { snapshotStore?.name }
    var isConnected: Bool { snapshotStore != nil }

    /// Eine Ablage anbinden — und sofort abgleichen.
    ///
    /// **Pull, Merge, Push.** Niemals andersherum: das iPhone, das sich zum
    /// ersten Mal verbindet, darf nicht zuerst seinen eigenen Stand hochladen
    /// und damit löschen, was der Fernseher dort schon abgelegt hat.
    /// `startSync` nur für Tests: dort soll der Ablauf abgewartet werden
    /// können, statt nebenher zu laufen. Die App lässt es bei `true` — sonst
    /// wäre genau die Reihenfolge verletzt, um die es hier geht.
    func connect(to store: LibrarySnapshotStore, accountId: String? = nil, startSync: Bool = true) {
        if let accountId, bookkeeping.syncValue(forKey: Self.accountKey) != accountId {
            // Anderes Google-Konto: ein anderer Sync-Raum. Die gemerkte
            // Dateikennung zeigt auf eine Datei, die es dort nicht gibt.
            bookkeeping.setSyncValue(nil, forKey: Self.fileIdKey)
            bookkeeping.setSyncValue(accountId, forKey: Self.accountKey)
            cache = [:]
        }
        snapshotStore = store
        status = .idle
        if startSync { syncNow() }
    }

    /// Dieses Gerät trennen.
    ///
    /// Ausdrücklich **nicht**: die Bibliothek löschen, die Drive-Datei löschen
    /// oder andere Geräte abmelden. „Trennen" heißt, dass dieses Gerät nicht
    /// mehr abgleicht — alles andere bleibt, wie es ist.
    func disconnect() {
        debounceTask?.cancel()
        debounceTask = nil
        stopPolling()
        snapshotStore = nil
        cache = [:]
        bookkeeping.setSyncValue(nil, forKey: Self.fileIdKey)
        status = .disconnected
        lastError = nil
        lastWarning = nil
    }

    // MARK: - Auslöser

    /// Der Store hat etwas geändert.
    ///
    /// `duringPlayback` unterscheidet die beiden Takte: ein Häkchen in der
    /// Merkliste darf nach ein paar Sekunden oben sein, ein Fortschritt, der
    /// im Sekundentakt fortschreibt, nicht.
    func noteChange(duringPlayback: Bool = false) {
        guard snapshotStore != nil else { return }
        hasPendingChanges = true
        if duringPlayback {
            let elapsed = (clock() - lastUploadAt) / 1000
            guard elapsed >= Self.playbackInterval else { return }
        }
        scheduleSync(after: duringPlayback ? 0 : Self.debounce)
    }

    /// Sofort: Pause, Player verlassen, Folge beendet, App in den Hintergrund,
    /// Merkliste geändert, „Jetzt synchronisieren".
    func syncNow() {
        debounceTask?.cancel()
        debounceTask = nil
        Task { await run() }
    }

    /// Im Vordergrund regelmäßig nach fremden Änderungen sehen.
    ///
    /// Ein Zeitgeber, nicht zehn über die App verteilte. Die Wartezeit steht in
    /// `foregroundPoll` und sonst nirgends — wer sie ändern will, ändert sie an
    /// einer Stelle.
    ///
    /// Für Version 1 ausdrücklich kein Drive-Changes-Feed: bei vier kleinen
    /// Dateien kostet `files.list` weniger als der Aufwand, einen Änderungs-
    /// zeiger zu führen und richtig zu halten.
    func startPolling() {
        guard pollTask == nil, snapshotStore != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.foregroundPoll * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.run()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func scheduleSync(after seconds: Double) {
        debounceTask?.cancel()
        guard seconds > 0 else { syncNow(); return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    // MARK: - Ablauf

    /// Ein vollständiger Abgleich.
    ///
    /// Läuft schon einer, wird nicht ein zweiter gestartet, sondern gemerkt,
    /// dass danach noch einmal gelaufen werden muss. Ohne das entstünden bei
    /// fünf schnellen Änderungen fünf parallele Abgleiche, die sich gegenseitig
    /// überholen.
    func run() async {
        guard let remote = snapshotStore else { return }
        guard !running else { pending = true; return }
        running = true
        defer {
            running = false
            if pending {
                pending = false
                Task { await run() }
            }
        }

        status = .syncing
        do {
            let pulled = try await pullAndMerge(from: remote)
            guard let pulled else { return }  // Status ist bereits gesetzt
            store.applyMerged(pulled.merged)

            // Der eigene Stand wird **nach** dem Anwenden gebildet. Sonst
            // fehlte darin genau das, was gerade zusammengeführt wurde.
            let own = store.snapshot()
            let payload = try JSONEncoder().encode(own)
            guard payload.count <= LibrarySyncLimits.maxSnapshotBytes else {
                throw GoogleDriveError.tooLarge(payload.count)
            }
            let written = try await upload(payload, to: remote, known: pulled.refs)
            bookkeeping.setSyncValue(written.id, forKey: Self.fileIdKey)
            // Der eigene Stand ist damit bekannt. Ohne diesen Eintrag lädt der
            // nächste Abgleich die gerade selbst geschriebene Datei wieder
            // herunter — jedes Mal, für nichts.
            cache[written.id] = (written.modifiedTime, own)

            lastUploadAt = clock()
            lastSuccessfulSync = lastUploadAt
            hasPendingChanges = false
            lastError = nil
            status = .idle
        } catch let error as GoogleDriveError {
            apply(error)
        } catch {
            // Netzfehler sehen von hier aus alle gleich aus: nichts ist
            // verloren, es wird später erneut versucht.
            status = .offline
            lastError = error.localizedDescription
        }
    }

    /// Alles holen, was da ist, und mit dem **jetzigen** lokalen Stand
    /// verrechnen.
    ///
    /// „Jetzig" ist der Punkt: zwischen `list()` und hier vergehen Sekunden,
    /// und in denen läuft die Wiedergabe weiter. Würde gegen eine Kopie von
    /// vorhin zusammengeführt, setzte der Abgleich den Fortschritt zurück, den
    /// der Spieler gerade geschrieben hat.
    private func pullAndMerge(
        from remote: LibrarySnapshotStore
    ) async throws -> (merged: LibraryData, refs: [RemoteSnapshotRef])? {
        let refs = try await remote.list()
        var snapshots: [LibraryData] = []
        var warning: String?
        var fresh: [String: (modifiedTime: String, data: LibraryData)] = [:]

        for ref in refs {
            if let cached = cache[ref.id], cached.modifiedTime == ref.modifiedTime {
                fresh[ref.id] = cached
                snapshots.append(cached.data)
                continue
            }
            guard ref.size <= LibrarySyncLimits.maxSnapshotBytes else {
                warning = "Ein Gerätestand ist unerwartet groß (\(ref.size) Bytes) und wurde übergangen."
                continue
            }
            let data: Data
            do {
                data = try await remote.download(ref)
            } catch let error as GoogleDriveError where error == .notFound {
                // Zwischen Auflisten und Holen gelöscht. Kein Fehler.
                continue
            }
            guard let decoded = try? JSONDecoder().decode(LibraryData.self, from: data) else {
                // Eine unlesbare Fremddatei nimmt nur sich selbst mit. Den
                // lokalen Stand mit ihr zu überschreiben wäre der teuerste
                // denkbare Fehler.
                warning = "Ein Gerätestand war nicht lesbar und wurde übergangen."
                continue
            }
            if (decoded.version ?? 1) > LibraryStore.schemaVersion {
                // Eine neuere App hat hier geschrieben. Diese Version würde
                // beim Hochladen Felder wegwerfen, die sie nicht kennt — also
                // wird gar nicht hochgeladen.
                status = .unsupportedRemoteVersion
                lastError = "In der Cloud liegt ein neuerer Stand (Schema \(decoded.version ?? 0)). Nori muss aktualisiert werden."
                return nil
            }
            fresh[ref.id] = (ref.modifiedTime, decoded)
            snapshots.append(decoded)
        }

        cache = fresh
        lastWarning = warning
        // Der lokale Stand kommt zuletzt dazu und hat keinen Sonderrang — das
        // Ergebnis ist dasselbe, wenn er zuerst käme.
        return (mergeLibrarySnapshots(snapshots + [store.snapshot()], now: clock()), refs)
    }

    private func upload(
        _ payload: Data,
        to remote: LibrarySnapshotStore,
        known refs: [RemoteSnapshotRef]
    ) async throws -> RemoteSnapshotRef {
        // Die gemerkte Kennung zuerst; ist keine da, die eigene Datei am
        // Gerätekennzeichen wiedererkennen.
        //
        // Der zweite Weg ist der wichtige. Ohne ihn legte jede erneute
        // Zustimmung — und jede Neuinstallation mit erhaltener Bibliothek —
        // eine zweite Datei für dasselbe Gerät an, und der Ordner füllte sich
        // mit Karteileichen.
        let fileId = bookkeeping.syncValue(forKey: Self.fileIdKey)
            ?? refs.first { $0.deviceId == store.deviceId }?.id
        do {
            return try await remote.upload(payload, deviceId: store.deviceId, fileId: fileId)
        } catch let error as GoogleDriveError where error == .notFound {
            // Zwischen Auflisten und Schreiben gelöscht. Eine neue anlegen
            // statt aufzugeben.
            bookkeeping.setSyncValue(nil, forKey: Self.fileIdKey)
            return try await remote.upload(payload, deviceId: store.deviceId, fileId: nil)
        }
    }

    private func apply(_ error: GoogleDriveError) {
        switch error {
        case .notAuthorized:
            status = .error("Die Verbindung zu Google ist abgelaufen. Bitte neu verbinden.")
            lastError = "notAuthorized"
        case .forbidden(let reason):
            status = .error("Google hat den Zugriff abgelehnt\(reason.isEmpty ? "" : " (\(reason))").")
            lastError = reason
        case .transport(let message):
            status = .offline
            lastError = message
        case .tooLarge(let bytes):
            status = .error("Der Stand ist mit \(bytes) Bytes zu groß für den Abgleich.")
            lastError = "tooLarge"
        case .notFound, .conflict, .http:
            status = .error("Der Abgleich ist fehlgeschlagen.")
            lastError = "\(error)"
        }
    }
}

/// Die Gerätestände im `appDataFolder`.
///
/// Dünn mit Absicht: hier steht, *wo* die Dateien liegen und wie sie heißen.
/// Wie HTTP funktioniert, weiß `GoogleDriveClient`; was in den Dateien steht,
/// weiß `LibrarySync`.
final class GoogleDriveSnapshotStore: LibrarySnapshotStore, @unchecked Sendable {
    let name = "Google Drive"
    private let client: GoogleDriveClient

    init(client: GoogleDriveClient) { self.client = client }

    func list() async throws -> [RemoteSnapshotRef] {
        try await client.listSnapshots()
            .filter(GoogleDriveClient.isSnapshot)
            .map { RemoteSnapshotRef(id: $0.id, deviceId: $0.deviceId, modifiedTime: $0.modifiedTime, size: $0.size) }
    }

    func download(_ ref: RemoteSnapshotRef) async throws -> Data {
        try await client.download(id: ref.id, expectedSize: ref.size)
    }

    func upload(_ data: Data, deviceId: String, fileId: String?) async throws -> RemoteSnapshotRef {
        if let fileId {
            let modifiedTime = try await client.update(id: fileId, content: data)
            return RemoteSnapshotRef(id: fileId, deviceId: deviceId, modifiedTime: modifiedTime, size: data.count)
        }
        let created = try await client.create(
            name: GoogleDriveClient.snapshotName(deviceId: deviceId),
            deviceId: deviceId,
            content: data
        )
        return RemoteSnapshotRef(id: created.id, deviceId: deviceId, modifiedTime: created.modifiedTime, size: data.count)
    }
}
