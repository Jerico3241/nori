import Foundation

/// Auswahl unter mehreren TMDB-Bildern und das Auffüllen lückenhafter Texte.
///
/// Beides sind reine Funktionen über bereits geholten Antworten — sie lagen
/// vorher mitten im Netzcode und waren damit nur über eine echte HTTP-Antwort
/// erreichbar, also nicht prüfbar.
enum TMDBArtwork {

    // MARK: - Logos

    /// Die Rangfolge der Logosprachen.
    ///
    /// Deutsch vor Englisch vor **sprachlos** vor allem anderen. Der dritte
    /// Rang ist der wichtige: ein Logo ohne Sprachkennzeichen ist bei Anime
    /// oft das einzige und meist der freigestellte Originalschriftzug — es
    /// gehört vor ein thailändisches, nicht mit ihm auf eine Stufe.
    ///
    /// Vorher fielen `null` und „irgendeine Sprache" in denselben Rang, und
    /// welches davon gewann, entschied die Bewertung.
    static func languageRank(_ iso: String?) -> Int {
        switch iso {
        case "de": return 0
        case "en": return 1
        case nil, "": return 2
        default: return 3
        }
    }

    /// Das brauchbarste Logo aus einer `/images`-Antwort.
    ///
    /// **PNG vor SVG**, genauer: SVG fällt ganz heraus — `AsyncImage` stellt
    /// es nicht dar, ein SVG-Logo bliebe unsichtbar. Danach die Sprache, erst
    /// zuletzt die Bewertung.
    static func bestLogoPath(_ rows: [[String: Any]]) -> String? {
        let usable = rows.filter { row in
            guard let path = row["file_path"] as? String, !path.isEmpty else { return false }
            return !path.lowercased().hasSuffix(".svg")
        }
        guard !usable.isEmpty else { return nil }
        return usable
            .sorted { a, b in
                let ra = languageRank(a["iso_639_1"] as? String)
                let rb = languageRank(b["iso_639_1"] as? String)
                if ra != rb { return ra < rb }
                let va = a["vote_average"] as? Double ?? 0
                let vb = b["vote_average"] as? Double ?? 0
                if va != vb { return va > vb }
                return (a["vote_count"] as? Int ?? 0) > (b["vote_count"] as? Int ?? 0)
            }
            .first?["file_path"] as? String
    }

    // MARK: - Texte

    /// Der erste Wert, der wirklich etwas enthält.
    ///
    /// Der Unterschied zwischen `nil` und `""` ist hier der ganze Punkt: TMDB
    /// liefert für eine Folge ohne deutsche Beschreibung nicht etwa gar kein
    /// Feld, sondern `"overview": ""`. Eine Prüfung auf „ist gesetzt" hält das
    /// für eine Auskunft und verwirft die englische Beschreibung, die es gibt.
    static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// Eine Folge aus einer zweiten Sprachfassung auffüllen.
    ///
    /// Füllt **nur Lücken**: Was auf Deutsch dasteht, bleibt stehen. Ergänzt
    /// werden auch `airDate` und `runtime` — die hängen nicht an der Sprache,
    /// fehlten aber bisher im Zusammenführen und gingen dadurch verloren,
    /// wenn die deutsche Fassung eine Folge gar nicht führte.
    ///
    /// Ein Platzhaltertitel („Folge 11") zählt dabei als Lücke: die englische
    /// Fassung trägt dort oft den echten Titel.
    static func filling(_ primary: EpisodeInfo, with fallback: EpisodeInfo) -> EpisodeInfo {
        var out = primary
        if out.namedTitle == nil, EpisodeInfo(title: fallback.title).namedTitle != nil {
            out.title = fallback.title
        }
        if firstNonEmpty(out.title) == nil { out.title = fallback.title }
        if firstNonEmpty(out.overview) == nil { out.overview = fallback.overview }
        if firstNonEmpty(out.still) == nil { out.still = fallback.still }
        if firstNonEmpty(out.airDate) == nil { out.airDate = fallback.airDate }
        if out.runtime == nil { out.runtime = fallback.runtime }
        return out
    }

    /// Zwei Sprachfassungen einer ganzen Staffel zusammenführen.
    ///
    /// Die frühere Regel war eine Schwelle über die **ganze** Staffel: erst
    /// wenn mehr als der Hälfte der Folgen die deutsche Beschreibung fehlte,
    /// wurde überhaupt eine englische Fassung geholt. Eine Staffel, in der
    /// genau eine Folge keinen deutschen Text hat, blieb damit lückenhaft,
    /// obwohl der englische Text vorlag — gemessen etwa an *Dan Da Dan*,
    /// Staffel 1: 23 von 24 deutschen Beschreibungen, die 24. blieb leer.
    ///
    /// Jetzt entscheidet jede Folge und jedes Feld für sich.
    static func merging(_ primary: [Int: EpisodeInfo], with fallback: [Int: EpisodeInfo]) -> [Int: EpisodeInfo] {
        var out = primary
        for (number, info) in fallback {
            if let mine = out[number] {
                out[number] = filling(mine, with: info)
            } else {
                out[number] = info
            }
        }
        return out
    }

    /// Fehlt der Staffel etwas, das eine zweite Sprachfassung liefern könnte?
    ///
    /// Wird gebraucht, um den zweiten Abruf zu sparen, wenn nichts fehlt —
    /// und ihn sonst **immer** zu machen, nicht erst ab einer Schwelle.
    static func hasGaps(_ episodes: [Int: EpisodeInfo]) -> Bool {
        episodes.isEmpty || episodes.values.contains { info in
            info.namedTitle == nil
                || firstNonEmpty(info.overview) == nil
                || firstNonEmpty(info.still) == nil
        }
    }
}
