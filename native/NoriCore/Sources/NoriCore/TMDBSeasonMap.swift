import Foundation

/// Die Zuordnung zwischen der Staffelzählung der Quelle und der von TMDB.
///
/// ## Warum das nötig ist
///
/// `season_number` und `episode_number` sind keine gemeinsame Sprache.
/// Gemessen an TMDB (Stand der Untersuchung):
///
/// - **Jujutsu Kaisen** führt TMDB als **eine** Staffel mit 59 Folgen.
///   AniWorld führt Staffel 1 und Staffel 2. `/tv/95479/season/2` antwortet
///   mit **HTTP 404**.
/// - **Detektiv Conan**: eine TMDB-Staffel mit 1213 Folgen, bei der Quelle
///   über ein Dutzend Staffeln. Ab Staffel 2 gab es nie Folgendaten.
/// - **Frieren**: eine TMDB-Staffel mit 38 Folgen.
///
/// Das war kein Randfall, sondern der Normalfall bei Anime: Sobald die Quelle
/// feiner unterteilt als TMDB, lief jede Folge ab der zweiten Staffel ins
/// Leere — und wurde dort als „TMDB hat nichts" dauerhaft abgelegt.
///
/// ## Wie hier zugeordnet wird
///
/// Nicht über die Nummer, sondern über die **Folgentitel**. Die Quelle kennt
/// zu jeder Folge einen deutschen und einen englischen Titel; TMDB kennt
/// seine eigenen. Stimmen mehrere davon bei einem festen Versatz überein,
/// ist der Versatz belegt und nicht geraten.
///
/// Findet sich kein belegter Versatz, wird **nichts** zugeordnet. Ein falsches
/// Standbild ist schlechter als keines.
enum TMDBSeasonMap {
    /// Eine Folge, wie die Quelle sie führt.
    struct SourceEpisode: Hashable {
        var number: Int
        /// Alle Schreibweisen, die die Quelle kennt — deutsch und englisch.
        var titles: [String]

        init(number: Int, titles: [String]) {
            self.number = number
            self.titles = titles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    /// Mindestens so viele übereinstimmende Titel, sonst gilt nichts als belegt.
    static let minimumAnchors = 3

    /// Und mindestens dieser Anteil der benennbaren Quellfolgen.
    static let minimumShare = 0.5

    /// Der Versatz zwischen Quellnummer und TMDB-Nummer, oder `nil`.
    ///
    /// `tmdbNummer = quellNummer + versatz`. Ein Versatz von 0 heißt, dass
    /// beide Seiten gleich zählen.
    ///
    /// - Parameters:
    ///   - source: Die Folgen der Quelle in dieser Staffel.
    ///   - tmdb: Folgennummer zu Folgentitel, wie TMDB sie führt.
    static func offset(source: [SourceEpisode], tmdb: [Int: String]) -> Int? {
        // Nach Titel geschlüsselt: sonst wäre die Suche für eine Staffel mit
        // 1200 Folgen ein Vergleich jeder Folge mit jeder.
        var byTitle: [String: [Int]] = [:]
        for (number, raw) in tmdb {
            let key = TMDBMatcher.normalize(raw)
            guard key.count >= 3, !isPlaceholder(raw) else { continue }
            byTitle[key, default: []].append(number)
        }
        guard !byTitle.isEmpty else { return nil }

        var namedSources = 0
        var tally: [Int: Int] = [:]
        for episode in source {
            let keys = episode.titles
                .map(TMDBMatcher.normalize)
                .filter { $0.count >= 3 }
            guard !keys.isEmpty else { continue }
            namedSources += 1
            // Pro Quellfolge zählt jeder Versatz höchstens einmal — sonst
            // zählte eine Folge, deren deutscher und englischer Titel bei
            // TMDB gleich heißen, doppelt.
            var seen: Set<Int> = []
            for key in keys {
                for number in byTitle[key] ?? [] where seen.insert(number - episode.number).inserted {
                    tally[number - episode.number, default: 0] += 1
                }
            }
        }
        guard namedSources > 0 else { return nil }

        let ranked = tally.sorted { $0.value == $1.value ? abs($0.key) < abs($1.key) : $0.value > $1.value }
        guard let best = ranked.first else { return nil }
        guard best.value >= min(minimumAnchors, namedSources) else { return nil }
        guard Double(best.value) >= Double(namedSources) * minimumShare else { return nil }
        // Ein zweiter Versatz mit gleich vielen Belegen ist keine Zuordnung,
        // sondern ein Münzwurf. Häufig bei Serien, deren Folgen alle „Folge n"
        // heißen — die filtert `isPlaceholder` zwar heraus, aber nicht jede
        // Wiederholung.
        if ranked.count > 1, ranked[1].value == best.value { return nil }
        return best.key
    }

    /// Wie viele der Quellfolgen die TMDB-Antwort überhaupt abdeckt.
    ///
    /// Entscheidet, ob eine Antwort mit HTTP 200 trotzdem die falsche Staffel
    /// ist: Wenn die Quelle 48 Folgen führt und TMDB in derselben Staffel 24,
    /// bleibt die Hälfte ohne Daten, obwohl TMDB sie in der Folgestaffel hat.
    static func coverage(source: [SourceEpisode], tmdb: [Int: EpisodeInfo]) -> Double {
        guard !source.isEmpty else { return tmdb.isEmpty ? 0 : 1 }
        let hit = source.filter { tmdb[$0.number] != nil }.count
        return Double(hit) / Double(source.count)
    }

    /// Die TMDB-Folgen auf die Nummern der Quelle umschreiben.
    static func remap(_ tmdb: [Int: EpisodeInfo], by offset: Int, to source: [SourceEpisode]) -> [Int: EpisodeInfo] {
        var out: [Int: EpisodeInfo] = [:]
        for episode in source {
            if let info = tmdb[episode.number + offset] { out[episode.number] = info }
        }
        return out
    }

    /// Ist der Titel nur die Nummer in Worten?
    ///
    /// TMDB füllt unbenannte Folgen mit „Folge 11" bzw. „Episode 11". Als
    /// Anker wären sie wertlos und obendrein irreführend: sie stimmen bei
    /// jedem Versatz mit irgendetwas überein.
    static func isPlaceholder(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: #"^(folge|episode|ep|eps)\s*\d+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

extension Array where Element == Episode {
    /// Die Folgen der Quelle in der Form, die `TMDBSeasonMap` braucht.
    ///
    /// Beide Titel werden mitgegeben: AniWorld führt zu einer Folge einen
    /// deutschen **und** einen englischen, und welcher davon dem TMDB-Titel
    /// entspricht, hängt an der Serie. Als Anker taugt jeder.
    var tmdbSourceEpisodes: [TMDBSeasonMap.SourceEpisode] {
        map { TMDBSeasonMap.SourceEpisode(number: $0.number, titles: [$0.germanTitle, $0.englishTitle]) }
    }
}
