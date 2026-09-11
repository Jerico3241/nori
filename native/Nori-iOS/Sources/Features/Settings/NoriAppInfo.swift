import SwiftUI
import UIKit

// Auskunft über die laufende App, die Bildablage und den Zustand der Dienste.
//
// Alles hier wird **gemessen oder gefragt**, nichts geschrieben. Die Vorlage
// zeigt „428 MB" und „Verbunden" als festen Text; hier kommt die Zahl aus dem
// Dateisystem und der Zustand aus einer Anfrage, die auch fehlschlagen darf.

// MARK: - Version

/// Version, Build und Plattform — aus dem Bundle, nicht aus dem Quelltext.
///
/// `MARKETING_VERSION` des Xcode-Projekts ist laut Projektregeln die einzige
/// Quelle der App-Version. Sie landet als `CFBundleShortVersionString` im
/// Bundle, und genau von dort wird sie hier gelesen. Eine Zeichenkette als
/// Rückfall gäbe es nicht: sie wäre eine zweite Wahrheit und würde irgendwann
/// abweichen.
enum NoriBuild {
    static var version: String {
        string("CFBundleShortVersionString") ?? "—"
    }

    static var build: String {
        string("CFBundleVersion") ?? "—"
    }

    static var platform: String {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion)"
    }

    /// Der Bundle-Bezeichner. Keine Geheimnis-, sondern eine Einordnungsfrage:
    /// auf einem Gerät mit mehreren Nori-Installationen sagt er, welche läuft.
    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "—"
    }

    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty
        else { return nil }
        return value
    }
}

// MARK: - Bildablage

/// Die Ablage für Poster, Breitbilder, Folgenbilder und Schriftzüge.
///
/// Nori hat keinen eigenen Bildordner: die Bilder gehen durch `URLSession` mit
/// der Standardkonfiguration und liegen damit im `URLCache` der App, dazu eine
/// begrenzte Menge entschlüsselt im Speicher (`CoverImageLoader`). Beides wird
/// hier gemessen. Daneben liegen die Zuordnungstabellen als JSON —
/// `covers.json`, `episodes.json`, `tmdb-lists.json` —, die zwar keine Bilder
/// sind, aber zum selben Zwischenspeicher gehören und sich genauso neu
/// aufbauen.
///
/// `library.json` gehört **nicht** dazu und wird nie angefasst: dort stehen
/// Merkliste, Verlauf und Fortschritt.
enum NoriImageCache {
    /// Die Dateien, die sich jederzeit neu holen lassen.
    private static let regenerable = ["covers.json", "episodes.json", "tmdb-lists.json"]

    /// Bilder auf der Platte und im Speicher.
    static func measure() async -> Int64 {
        let disk = Int64(URLCache.shared.currentDiskUsage)
        let memory = await CoverImageLoader.shared.memoryBytes()
        return disk + memory
    }

    /// Die abgelegten Zuordnungstabellen.
    static func metadataBytes() -> Int64 {
        guard let folder = supportFolder() else { return 0 }
        var total: Int64 = 0
        for name in regenerable {
            let url = folder.appendingPathComponent(name)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    /// Alles Regenerierbare löschen.
    ///
    /// Die Ordner `CoverIndex` und `EpisodeIndex` halten ihre Tabellen
    /// zusätzlich im Speicher; die Dateien sind danach weg, die laufende
    /// Sitzung merkt das erst beim nächsten Start. Das ist kein Fehler, aber es
    /// gehört in den Hinweistext der Seite, damit die Zahl danach nicht
    /// unerwartet wieder wächst.
    static func clear() async {
        URLCache.shared.removeAllCachedResponses()
        await CoverImageLoader.shared.purge()
        guard let folder = supportFolder() else { return }
        for name in regenerable {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// „428 MB" — mit der Schreibweise des Systems, nicht selbst gerechnet.
    static func format(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "leer" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func supportFolder() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Nori", isDirectory: true)
    }
}

// MARK: - Diagnose

/// Prüft, was Nori zum Laufen braucht — und sagt, was davon gerade klemmt.
///
/// Jede Prüfung geht wirklich los. Kein Befund ist vorberechnet, und keiner
/// nennt ein Geheimnis: der TMDB-Schlüssel wird verwendet, aber nie angezeigt,
/// nicht gekürzt und nicht in eine Meldung geschrieben. Dasselbe gilt für
/// Kopfzeilen, Kekse und Weiterleitungen der Hoster.
enum NoriDiagnostics {
    enum Status {
        case ok
        case warning
        case error

        var symbol: String {
            switch self {
            case .ok: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }

        var label: String {
            switch self {
            case .ok: return "OK"
            case .warning: return "Warnung"
            case .error: return "Fehler"
            }
        }

        var color: Color {
            switch self {
            case .ok: return Color(red: 0.52, green: 0.85, blue: 0.70)
            case .warning: return Color(red: 0.95, green: 0.72, blue: 0.42)
            case .error: return Color(red: 0.93, green: 0.46, blue: 0.49)
            }
        }
    }

    struct Check: Identifiable {
        let id: String
        let title: String
        let status: Status
        /// Was gemessen wurde. Eine Zahl oder ein Satz — nie ein Schlüssel,
        /// ein Token oder eine vollständige Hoster-Adresse.
        let detail: String

        var isHealthy: Bool { status == .ok }
    }

    /// Alle Prüfungen, gleichzeitig.
    ///
    /// `progressCount` und `syncName` kommen von außen, damit die Diagnose den
    /// `LibraryStore` nicht selbst anfassen muss — er gehört dem Main-Actor,
    /// und eine Prüfung, die nebenher läuft, hätte ihn sonst mitzuziehen.
    static func runAll(progressCount: Int, favorites: Int, syncName: String?) async -> [Check] {
        async let aniworld = checkProvider(.aniworld)
        async let serienstream = checkProvider(.serienstream)
        async let tmdb = checkTMDB()
        let cache = await checkCache()
        return await [
            aniworld,
            serienstream,
            tmdb,
            cache,
            checkLibrary(progressCount: progressCount, favorites: favorites),
            checkSync(name: syncName),
        ]
    }

    /// Abrufen **und** auswerten: eine erreichbare Seite, deren Aufbau sich
    /// geändert hat, ist für Nori genauso kaputt wie eine nicht erreichbare.
    /// Der Kalender prüft beides in einem Zug.
    static func checkProvider(_ provider: CatalogProvider) async -> Check {
        do {
            let payload = try await AniworldClient.shared.getCalendar(provider: provider)
            let count = payload.upcoming.count + payload.recent.count
            return Check(
                id: provider.rawValue,
                title: provider.label,
                status: .ok,
                detail: "Erreichbar, Kalender gelesen — \(count) Einträge."
            )
        } catch {
            return Check(
                id: provider.rawValue,
                title: provider.label,
                status: .error,
                detail: error.localizedDescription
            )
        }
    }

    /// Ohne Schlüssel eine Warnung, nicht ein Fehler: Nori läuft dann mit den
    /// Covern der Quellen weiter, nur ohne Breitbilder und Folgentitel.
    static func checkTMDB() async -> Check {
        guard let key = TMDBKeyStore.current else {
            return Check(
                id: "tmdb",
                title: "TMDB",
                status: .warning,
                detail: "Kein Schlüssel hinterlegt. Nori verwendet die Cover der Quellen."
            )
        }
        var components = URLComponents(string: "https://api.themoviedb.org/3/configuration")
        components?.queryItems = [URLQueryItem(name: "api_key", value: key)]
        guard let url = components?.url else {
            return Check(id: "tmdb", title: "TMDB", status: .error, detail: "Adresse nicht bildbar.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                return Check(id: "tmdb", title: "TMDB", status: .ok, detail: "Metadatenquelle verbunden.")
            }
            // 401 heißt: der Schlüssel wird abgelehnt. Das ist eine Auskunft
            // über den Zustand, kein Abdruck des Schlüssels.
            let reason = code == 401 ? "Der hinterlegte Schlüssel wird abgelehnt." : "Antwort HTTP \(code)."
            return Check(id: "tmdb", title: "TMDB", status: .error, detail: reason)
        } catch {
            return Check(id: "tmdb", title: "TMDB", status: .error, detail: error.localizedDescription)
        }
    }

    static func checkCache() async -> Check {
        let images = await NoriImageCache.measure()
        let metadata = NoriImageCache.metadataBytes()
        return Check(
            id: "cache",
            title: "Bild-Cache",
            status: .ok,
            detail: "Bilder \(NoriImageCache.format(images)), Tabellen \(NoriImageCache.format(metadata))."
        )
    }

    /// Der Fortschrittsspeicher. Leer ist kein Fehler — auf einer frischen
    /// Installation ist er das Normale.
    static func checkLibrary(progressCount: Int, favorites: Int) -> Check {
        Check(
            id: "library",
            title: "Bibliothek",
            status: .ok,
            detail: "Schema v\(LibraryStore.schemaVersion), \(progressCount) Fortschrittseinträge, \(favorites) gemerkt."
        )
    }

    static func checkSync(name: String?) -> Check {
        guard let name else {
            return Check(
                id: "sync",
                title: "Abgleich",
                status: .warning,
                detail: "Kein Anbieter eingerichtet — die Bibliothek liegt nur auf diesem Gerät."
            )
        }
        return Check(id: "sync", title: "Abgleich", status: .ok, detail: "Anbieter: \(name).")
    }
}
