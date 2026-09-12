import Foundation

/// Warum ein TMDB-Abruf nichts ergeben hat.
///
/// ## Warum das ein eigener Typ ist
///
/// Bisher war jeder Fehlschlag dasselbe: `nil`, `[:]`, `[]`. Damit ließ sich
/// nicht mehr unterscheiden, ob TMDB eine Serie **nicht kennt** oder ob die
/// Anfrage gescheitert ist — und weil die Aufrufer den Fehlschlag dauerhaft
/// ablegten, machte eine einzige Ratenbegrenzung aus „gerade nicht erreichbar"
/// ein „gibt es nicht", und zwar bis zum Löschen des Caches.
///
/// Genau ein Fall rechtfertigt ein dauerhaftes Merken: HTTP 404. Alles andere
/// darf beim nächsten Versuch wieder gefragt werden.
enum TMDBFailure: Error, Equatable {
    /// Kein Schlüssel hinterlegt. Kein Fehler, sondern ein gültiger Zustand.
    case noKey
    /// 404 — die Kennung oder die Staffel gibt es dort nicht.
    case notFound
    /// 401/403 — der Schlüssel wird abgelehnt.
    case unauthorized
    /// 429 — zu viele Anfragen.
    case rateLimited
    /// 5xx.
    case server(Int)
    /// Zeitüberschreitung, kein Netz, abgebrochene Verbindung.
    case network
    /// Antwort kam an, ließ sich aber nicht lesen.
    case malformed

    /// Darf dieser Fehlschlag dauerhaft als „hat TMDB nicht" abgelegt werden?
    ///
    /// Nur bei 404. Ein ungültiger Schlüssel wird ersetzt, eine
    /// Ratenbegrenzung läuft ab, ein Netzfehler vergeht — wer diese Fälle
    /// wegschreibt, schreibt Titel ab, die TMDB sehr wohl führt.
    var isDefinitive: Bool { self == .notFound }

    /// Für die Protokollzeile. Enthält nie einen Schlüssel.
    var label: String {
        switch self {
        case .noKey: return "kein Schlüssel"
        case .notFound: return "404"
        case .unauthorized: return "401/403"
        case .rateLimited: return "429"
        case .server(let code): return "HTTP \(code)"
        case .network: return "Netzfehler"
        case .malformed: return "unlesbare Antwort"
        }
    }

    /// Einen HTTP-Code auf einen Fehlschlag abbilden. `nil` heißt „in Ordnung".
    static func from(status code: Int) -> TMDBFailure? {
        switch code {
        case 200 ..< 300: return nil
        case 401, 403: return .unauthorized
        case 404: return .notFound
        case 429: return .rateLimited
        case 500 ..< 600: return .server(code)
        default: return .server(code)
        }
    }
}
