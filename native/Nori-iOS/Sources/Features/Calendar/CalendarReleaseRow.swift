import SwiftUI

/// Eine Veröffentlichung als Zeile: Standbild, Serie, Staffel und Folge,
/// Folgentitel, Uhrzeit, Sprachen.
///
/// ## Was hier von wem kommt
///
/// Serie, Staffel, Folgennummer, Sprachen und das Datum stammen von AniWorld
/// bzw. Serienstream — sie entscheiden, was es gibt. TMDB trägt Folgentitel und
/// Standbild nach, sofern ein Schlüssel hinterlegt ist und die Staffel dort
/// geführt wird. Fehlt beides, steht die Zeile mit dem Cover der Quelle und
/// ohne Folgentitel da; der Kalender bleibt vollständig benutzbar.
///
/// Nichts davon wird erfunden: keine Uhrzeit ohne genannte Uhrzeit, kein
/// Folgentitel ohne Fund, keine Sprache, die die Quelle nicht anbietet.
struct CalendarReleaseRow: View {
    let release: CalendarRelease
    /// Steht die Serie in der Merkliste? Als dezenter Marker, nicht als Abzeichen.
    let marked: Bool
    let width: CGFloat

    @State private var info: EpisodeInfo?

    var body: some View {
        HStack(spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 5) {
                titleLine
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11))
                        .foregroundStyle(NoriTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !release.languages.isEmpty {
                    languages
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NoriTheme.muted)
        }
        .padding(.vertical, 9)
        .task(id: metaKey) { await loadMeta() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOver)
    }

    // MARK: - Bestandteile

    private var titleLine: some View {
        HStack(spacing: 5) {
            Text(release.title)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if marked {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(NoriTheme.accent.opacity(0.8))
                    .accessibilityHidden(true)
            }
        }
    }

    /// „Staffel 1 · Folge 7 · Der stille Turm" — der Folgentitel nur, wenn ihn
    /// TMDB wirklich geliefert hat.
    private var meta: String {
        var parts: [String] = []
        let label = release.episodeLabel
        if !label.isEmpty { parts.append(label) }
        // `namedTitle` und nicht `title`: TMDB füllt unbenannte Folgen mit
        // „Folge 11" auf, und daraus wurde „Staffel 3 · Folge 11 · Folge 11".
        if let title = info?.namedTitle {
            parts.append(title)
        }
        return parts.joined(separator: " · ")
    }

    private var languages: some View {
        HStack(spacing: 4) {
            ForEach(release.languages, id: \.self) { code in
                Text(CalendarLanguage.label(code))
                    .font(.system(size: 8, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(NoriTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(NoriTheme.accent.opacity(0.18))
                    }
            }
        }
    }

    /// Das Bild. Standbild von TMDB, sonst das Cover der Quelle, sonst der
    /// Buchstabe — in dieser Reihenfolge, weil nur das Standbild die Folge
    /// zeigt und das Cover die Serie.
    private var thumb: some View {
        // Der Rahmen gehört dieser Ansicht, das Bild liegt als `overlay`
        // darin. So bestimmt das Bild die Größe nicht mit und kann nicht über
        // den Rahmen hinauswachsen.
        Color.clear
            .frame(width: width, height: width * 9 / 16)
            .overlay {
                if let url = artwork {
                    NoriCoverImage(url: url, referer: release.primaryProvider.origin + "/") {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .overlay(alignment: .bottomLeading) {
                if release.hasTime {
                    Text(release.airingAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9, weight: .heavy))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(NoriTheme.bg.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(NoriTheme.border)
                        }
                        .padding(7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
    }

    private var placeholder: some View {
        ZStack {
            NoriTheme.elevated
            Text(String(release.title.prefix(1)))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(NoriTheme.fg.opacity(0.16))
        }
    }

    private var artwork: URL? {
        if let still = info?.still, let url = URL(string: still) { return url }
        return AniworldClient.coverURL(release.coverPath, provider: release.primaryProvider)
    }

    // MARK: - TMDB

    /// Je Serie und Staffel einmal. Mehrere Folgen derselben Staffel an einem
    /// Tag fragen denselben Schlüssel und treffen denselben Zwischenspeicher.
    private var metaKey: String {
        "\(release.primaryProvider.rawValue)|\(release.slug)|\(release.season)"
    }

    /// Erst der abgelegte Stand, dann TMDB.
    ///
    /// Die kurze Pause vor dem Abruf ist Absicht: beim Durchscrollen bricht die
    /// Aufgabe vorher ab, und es geht gar keine Anfrage raus. Geholt wird nur,
    /// was stehen bleibt — sonst schickt eine Monatsliste beim ersten Wischen
    /// dreißig Anfragen los.
    private func loadMeta() async {
        let cached = await EpisodeIndex.shared.cached(slug: release.slug, season: release.season)
        if let hit = cached[release.episode] {
            info = hit
            return
        }
        info = nil
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let loaded = await EpisodeIndex.shared.load(
            slug: release.slug,
            title: release.title,
            season: release.season,
            kind: release.primaryProvider
        )
        guard !Task.isCancelled else { return }
        info = loaded[release.episode]
    }

    // MARK: - VoiceOver

    /// Eine gesprochene Zeile, in der nichts doppelt vorkommt und die Uhrzeit
    /// nur auftaucht, wenn es eine gibt.
    private var voiceOver: String {
        var parts: [String] = [release.title]
        let label = release.episodeLabel
        if !label.isEmpty { parts.append(label) }
        if let title = info?.namedTitle { parts.append(title) }
        if release.hasTime {
            parts.append(release.airingAt.formatted(date: .omitted, time: .shortened))
        }
        if !release.languages.isEmpty {
            parts.append(release.languages.map(CalendarLanguage.label).joined(separator: ", "))
        }
        if marked { parts.append("in der Merkliste") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Sprachen

/// Die Sprachkennungen der Quellen als lesbare Beschriftung.
///
/// Die Kennungen stammen aus `HTML.flagLabel` und sind kurz gehalten, weil sie
/// in `WatchProgress` und im Hosterfilter mitlaufen. In der Oberfläche sollen
/// sie ausgeschrieben stehen — „DE" ist ein Datenfeld, „Deutsch" eine Angabe.
/// Unbekannte Kennungen gehen unverändert durch, statt durch eine falsche
/// ersetzt zu werden.
enum CalendarLanguage {
    static func label(_ code: String) -> String {
        switch code {
        case "DE": return "Deutsch"
        case "GerSub": return "GerSub"
        case "EN": return "Englisch"
        case "JP": return "Japanisch"
        default: return code
        }
    }
}
