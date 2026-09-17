import Foundation

// Was der Player entscheidet, ohne etwas abzuspielen.
//
// Die Entsprechung zu `shared/nori-core/src/playback.ts`. Hier steht, was auf
// jedem Gerät gleich sein muss: wie lange der Countdown zur nächsten Folge
// läuft, und was nach einem gescheiterten Stream passiert.
//
// Ohne diese Datei stand beides dreimal da und dreimal anders: acht Sekunden
// Countdown auf iPhone und Mac, zehn auf dem Fernseher — und beim Hosterwechsel
// nach einem Fehler nahm `tryAlternativeHoster` einfach den nächsten der Liste,
// ohne zu merken, dass es derselbe war, der eben nicht funktioniert hat. Zwei
// kaputte Hoster hintereinander ließen sich so endlos abwechselnd anbieten.
//
// Nichts hier macht Netzwerkarbeit. Die Wiederherstellung ist eine
// Zustandsmaschine aus reinen Funktionen: der Aufrufer meldet einen
// Fehlschlag, fragt nach dem nächsten Schritt und führt ihn aus.

// MARK: - Nächste Folge

enum Playback {
    /// Sekunden Countdown, bevor die nächste Folge startet.
    ///
    /// Steht auch in `config/contract.json` unter `rules.autoplay` und in
    /// `shared/nori-core/src/playback.ts`. Wer den Wert ändert, ändert ihn an
    /// allen drei Stellen.
    static let autoplayCountdownSec = 10

    /// Ab wie viel Rest einer Folge der Countdown angeboten wird.
    ///
    /// Die Folge gilt ab 90 % als abgeschlossen (`isEpisodeComplete`); der
    /// Countdown erscheint erst kurz vor dem Ende, damit er nicht über einem
    /// Abspann von zehn Minuten Rest hängt.
    static let autoplayTailSec: Double = 30

    /// Soll der Countdown jetzt laufen?
    static func shouldOfferNextEpisode(
        positionSec: Double,
        durationSec: Double,
        hasNext: Bool,
        autoplayEnabled: Bool
    ) -> Bool {
        guard hasNext, autoplayEnabled, durationSec >= 20 else { return false }
        return positionSec >= durationSec - autoplayTailSec
    }
}

// MARK: - Quellen und Fehlschläge

/// Eine Quelle, so wie sie sich wiedererkennen lässt.
struct SourceRef: Hashable {
    var hoster: String
    var lang: String

    init(hoster: String, lang: String) {
        self.hoster = hoster
        self.lang = lang
    }

    /// „voe|de" — kleingeschrieben, damit Schreibweisen der Quellen nicht trennen.
    var key: String { "\(hoster.lowercased())|\(lang.lowercased())" }
}

/// Was nach einem Fehlschlag zu tun ist.
enum RecoveryStep: Equatable {
    /// Dieselbe Quelle noch einmal — ein Abbruch kann ein Aussetzer gewesen sein.
    case retry
    /// Eine andere Quelle.
    case switchTo(HosterOption)
    /// Nichts mehr übrig. Der Text steht so in der Oberfläche.
    case giveUp(String)
}

/// Der Stand der Wiederherstellung für **eine** Folge.
struct PlaybackRecovery: Equatable {
    /// Wie viele Quellen je Folge automatisch durchprobiert werden.
    ///
    /// Eine Grenze, weil ein Hoster, der eine Schutzseite ausliefert, das für
    /// alle tut: ohne sie liefe der Player die ganze Liste durch, jedes Mal mit
    /// einem vollständigen Abruf, und der Player hinge minutenlang in
    /// „Stream wird geholt …".
    static let maxAutomaticSwitches = 3

    /// Wie oft dieselbe Quelle nach einem Fehlschlag noch einmal versucht wird.
    static let maxSameSourceRetries = 1

    /// Quellen, die für diese Folge schon gescheitert sind.
    private(set) var failed: Set<String> = []
    /// Wie viele automatische Wechsel bisher stattfanden.
    private(set) var switches = 0
    /// Wie oft die aktuelle Quelle schon wiederholt wurde.
    private(set) var sameRetries = 0
    /// Zu welcher Folge der Stand gehört — `provider|episodePath`.
    private(set) var episode: String

    init(episode: String = "") {
        self.episode = episode
    }

    /// Den Stand auf eine Folge setzen. Bei einer anderen Folge beginnt er neu:
    /// dass VOE bei Folge 3 nichts lieferte, sagt über Folge 4 nichts.
    mutating func begin(episode: String) {
        guard self.episode != episode else { return }
        self = PlaybackRecovery(episode: episode)
    }

    /// Eine Quelle ist gescheitert.
    mutating func noteFailure(_ current: SourceRef?) {
        if let current { failed.insert(current.key) }
        sameRetries += 1
    }

    /// Eine Quelle spielt. Der Zähler für Wiederholungen fällt zurück, die
    /// Liste der gescheiterten bleibt — sie gilt weiter für diese Folge.
    mutating func noteSuccess() {
        sameRetries = 0
    }

    /// Ein Wechsel wurde ausgeführt.
    mutating func noteSwitch() {
        switches += 1
        sameRetries = 0
    }

    /// Welche Quellen noch übrig sind — in der Rangfolge, ohne die gescheiterten.
    ///
    /// `lang` grenzt auf die laufende Sprache ein; ohne Angabe zählen alle. Die
    /// Oberfläche benutzt dieselbe Liste für „Andere Quelle", damit dort nichts
    /// steht, was der Player gerade ausgeschlossen hat.
    func remaining(
        _ options: [HosterOption],
        lang: String? = nil,
        preferred: String? = nil
    ) -> [HosterOption] {
        let pool: [HosterOption]
        if let lang {
            pool = options.filter { $0.lang.lowercased() == lang.lowercased() }
        } else {
            pool = options
        }
        return HosterResolver.ordered(pool, preferred: preferred)
            .filter { !failed.contains(SourceRef(hoster: $0.name, lang: $0.lang).key) }
    }

    /// Was nach einem Fehlschlag zu tun ist.
    ///
    /// Eine Quelle, der ein Fehlschlag **zugeordnet** werden konnte, ist damit
    /// verbraucht: es geht zur nächsten in der Rangfolge aus
    /// `config/contract.json`, ohne die schon gescheiterten. Wiederholt wird
    /// nur, was sich nicht zuordnen ließ — ein Abbruch, bevor überhaupt ein
    /// Hoster feststand, ist meistens das Netz und nicht die Quelle.
    ///
    /// Bewusst **keine** zweite Runde je Hoster: jeder Versuch ist ein
    /// vollständiger Abruf, und vier davon dauern schon lange genug. Wer eine
    /// gescheiterte Quelle trotzdem will, wählt sie von Hand — die Auswahl in
    /// der Bedienung bleibt vollständig.
    ///
    /// Ist das Budget aufgebraucht oder nichts mehr übrig, wird aufgegeben
    /// statt im Kreis gelaufen.
    func plan(
        options: [HosterOption],
        current: SourceRef?,
        preferred: String? = nil
    ) -> RecoveryStep {
        if let current, sameRetries <= Self.maxSameSourceRetries, !failed.contains(current.key) {
            return .retry
        }
        guard switches < Self.maxAutomaticSwitches else {
            return .giveUp("Mehrere Quellen hintereinander lieferten keinen Stream.")
        }
        guard let next = remaining(options, lang: current?.lang, preferred: preferred).first else {
            return .giveUp("Kein weiterer Hoster verfügbar.")
        }
        return .switchTo(next)
    }
}

// MARK: - Übersprungmarken

/// Ein Abschnitt, den man überspringen kann.
///
/// **Es gibt dafür heute keine Datenquelle.** Weder AniWorld noch Serienstream
/// nennen Zeitmarken, und TMDB kennt sie nicht. Erfundene Zeiten wären
/// schlimmer als keine: ein „Intro überspringen" nach festen 90 Sekunden
/// schneidet bei der Hälfte der Serien mitten in die Handlung.
///
/// Deshalb steht hier nur die Form — Modell, Prüfung und die Frage „liegt
/// gerade eine Marke an?". Wer später eine Quelle anbindet, füllt
/// `SkipSegmentSource` und muss an den Oberflächen nichts mehr bauen.
enum SkipKind: String, Codable, CaseIterable, Hashable {
    case intro
    case outro
    case recap

    var label: String {
        switch self {
        case .intro: return "Intro überspringen"
        case .outro: return "Abspann überspringen"
        case .recap: return "Rückblick überspringen"
        }
    }
}

struct SkipSegment: Codable, Hashable {
    var type: SkipKind
    /// Sekunden seit Beginn der Folge.
    var start: Double
    var end: Double

    init(type: SkipKind, start: Double, end: Double) {
        self.type = type
        self.start = start
        self.end = end
    }
}

/// Worauf sich eine Marke bezieht.
struct SkipSegmentRef: Hashable {
    var provider: CatalogProvider
    var slug: String
    var season: String
    var episode: Int
    var durationSec: Double
}

/// Woher Marken kommen könnten. Umgesetzt ist bisher keine Quelle.
protocol SkipSegmentSource: Sendable {
    var name: String { get }
    func segments(for ref: SkipSegmentRef) async throws -> [SkipSegment]
}

enum SkipSegments {
    /// Marken auf Plausibilität prüfen.
    ///
    /// Eine fremde Quelle darf die Wiedergabe nicht kaputtmachen: negative
    /// Zeiten, vertauschte Grenzen, Marken jenseits der Laufzeit und solche
    /// unter zwei Sekunden fallen weg. Überlappende werden zusammengefasst.
    static func sanitize(_ raw: [SkipSegment], durationSec: Double) -> [SkipSegment] {
        let limit = durationSec > 0 ? durationSec : Double.greatestFiniteMagnitude
        let clean = raw
            .map { segment in
                SkipSegment(
                    type: segment.type,
                    start: max(0, min(segment.start, segment.end)),
                    end: min(limit, max(segment.start, segment.end))
                )
            }
            .filter { $0.end - $0.start >= 2 }
            .sorted { $0.start < $1.start }

        var out: [SkipSegment] = []
        for segment in clean {
            if let last = out.last, last.type == segment.type, segment.start <= last.end {
                out[out.count - 1].end = max(last.end, segment.end)
                continue
            }
            out.append(segment)
        }
        return out
    }

    /// Die Marke, die an dieser Stelle angeboten wird — oder keine.
    static func active(_ segments: [SkipSegment], at positionSec: Double) -> SkipSegment? {
        segments.first { positionSec >= $0.start && positionSec < $0.end }
    }
}
