import Foundation

/// Die Adressen der TMDB-Bilder — an einer Stelle.
///
/// TMDB liefert in seinen Antworten nur Pfade („/abc123.jpg"). Die vollständige
/// Adresse entsteht erst aus Host, Größenkürzel und Pfad, und genau dieses
/// Zusammensetzen stand bisher an fünf Stellen im Quelltext, jedes Mal mit
/// einer von Hand gewählten Breite. Zwei Folgen davon:
///
/// - Eine 132 Punkte breite Kachel lud ein 780 Pixel breites Poster. Bei
///   sechzig sichtbaren Kacheln sind das einige Megabyte für Bilder, die
///   ohnehin heruntergerechnet werden.
/// - Ändert TMDB Host oder Kürzel, gehört das an einer Stelle nachgezogen,
///   nicht an fünf.
///
/// Die Größen sind deshalb **nach Verwendungszweck** benannt, nicht nach
/// Pixeln: wer eine Posterkachel baut, soll nicht ausrechnen müssen, was
/// 132 Punkte auf einem 3×-Bildschirm in Pixeln sind.
///
/// TMDB führt die gültigen Kürzel in `/configuration`. Sie sind seit Jahren
/// unverändert und hier fest hinterlegt — ein zusätzlicher Abruf beim Start,
/// nur um „w342" zu erfahren, wäre eine Anfrage für nichts.
enum TMDBImages {
    private static let host = "https://image.tmdb.org/t/p/"

    /// Wofür das Bild gebraucht wird.
    ///
    /// Kein `String`-Rohwert: zwei Zwecke dürfen sich dasselbe TMDB-Kürzel
    /// teilen — ein 280 Punkte breites Breitbild und ein Poster als Kopfbild
    /// brauchen beide `w780` —, und ein Enum mit doppeltem Rohwert übersetzt
    /// nicht. Die Zuordnung steht deshalb in `segment`.
    enum Size {
        /// Kleine Kachel in einer Liste, rund 44 Punkte breit.
        case posterThumb
        /// Posterkachel einer Startseitenreihe, 132–168 Punkte breit.
        case posterCard
        /// Poster als Kopfbild, wenn kein Breitbild vorliegt.
        case posterHero
        /// Breitbild auf einer Weiterschauen-Kachel, rund 280 Punkte breit.
        case backdropCard
        /// Breitbild über die volle Bildschirmbreite.
        case backdropHero
        /// Freigestellter Schriftzug. Breiter als nötig lohnt nicht — er wird
        /// nie über 320 Punkte gezeigt.
        case logo
        /// Standbild einer Folge. TMDBs eigener 16:9-Zuschnitt.
        case still

        /// Das Kürzel, das TMDB in der Adresse erwartet.
        var segment: String {
            switch self {
            case .posterThumb: return "w185"
            case .posterCard: return "w342"
            case .posterHero: return "w780"
            case .backdropCard: return "w780"
            case .backdropHero: return "w1280"
            case .logo: return "w500"
            case .still: return "w454_and_h254_bestv2"
            }
        }
    }

    /// Vollständige Adresse zu einem TMDB-Bildpfad.
    ///
    /// Gibt `nil` zurück, wenn der Pfad fehlt oder leer ist — TMDB schreibt
    /// für ein fehlendes Bild `null`, manche Antworten auch `""`. Beides ist
    /// „kein Bild", nicht „Bild an der Adresse `…/t/p/w342`".
    static func url(_ path: String?, _ size: Size) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let clean = path.hasPrefix("/") ? path : "/" + path
        return URL(string: host + size.segment + clean)
    }

    /// Stammt eine Adresse von TMDB?
    ///
    /// Entscheidet, ob ein Bildabruf einen Referer braucht: AniWorld und
    /// Serienstream liefern ihre Cover nur mit passender Kopfzeile aus, TMDB
    /// verlangt keine. Bisher stand an jeder Aufrufstelle eine leere
    /// Zeichenkette als Referer, ohne dass erkennbar war, warum.
    static func isTMDB(_ url: URL) -> Bool {
        url.host?.hasSuffix("image.tmdb.org") == true
    }
}
