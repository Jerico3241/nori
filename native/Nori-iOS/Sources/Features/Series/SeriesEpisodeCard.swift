import SwiftUI

// Eine Folge als waagerechte Karte: Standbild, Nummer mit Titel, eine Zeile
// Eckdaten, Fortschritt.
//
// Die vorherige Zeile war eine Zeile — ein kleines Bild, Titel, drei Zeilen
// Beschreibung, rechts eine Prozentzahl. Diese hier ist eine Kachel mit
// eigenem Grund, und das Bild ist der größte Teil davon.

struct SeriesEpisodeCard: View {
    @Environment(LibraryStore.self) private var library

    let detail: SeriesDetail
    let episode: Episode
    let season: String
    let provider: CatalogProvider
    /// Standbild, Titel, Datum und Laufzeit von TMDB. `nil`, solange nichts
    /// geladen ist oder TMDB die Serie nicht führt — dann trägt die Karte,
    /// was die Quelle hergibt.
    let info: EpisodeInfo?
    /// Das Artwork der Serie. Steht ein, wo eine Folge kein eigenes Bild hat.
    let artwork: SeriesArtwork
    let tone: Color?
    /// Diese Folge würde „Jetzt ansehen" starten. Bekommt als einzige das
    /// Abspielzeichen auf dem Bild.
    let highlighted: Bool
    let width: CGFloat
    let play: (Episode, Double) -> Void

    var body: some View {
        let item = library.progress(
            slug: detail.slug, season: season, episode: episode.number, path: episode.path, provider: provider
        )
        let complete = isEpisodeComplete(item)
        let ratio = watchRatio(item)

        Button {
            play(episode, library.resumeEnabled ? resumePosition(item) : 0)
        } label: {
            HStack(spacing: 12) {
                thumb(complete: complete, ratio: ratio)

                VStack(alignment: .leading, spacing: 7) {
                    title
                    if let meta {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(1)
                            // Datum, Laufzeit und Sprache stehen auf einer
                            // Zeile, und die Spalte daneben ist schmal. Lieber
                            // eine Spur kleiner als mit „…" abgeschnitten:
                            // eine halbe Sprachangabe ist keine.
                            .minimumScaleFactor(0.72)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                SeriesProgressRing(ratio: ratio, complete: complete, tone: tone)
            }
            .padding(10)
            .frame(minHeight: thumbHeight + 22)
            .background {
                RoundedRectangle(cornerRadius: SeriesMetrics.card, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NoriTheme.elevated.opacity(0.96), NoriTheme.surface.opacity(0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: SeriesMetrics.card, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: SeriesMetrics.card, style: .continuous))
        }
        .buttonStyle(NoriPressStyle(scale: 0.985))
        .accessibilityLabel(accessibleLabel(complete: complete, ratio: ratio))
        .contextMenu {
            Button {
                library.markEpisode(episode, season: season, slug: detail.slug, title: detail.title, provider: provider, completed: true)
            } label: {
                Label("Als gesehen markieren", systemImage: "checkmark.circle")
            }
            Button {
                library.markEpisode(episode, season: season, slug: detail.slug, title: detail.title, provider: provider, completed: false)
            } label: {
                Label("Als ungesehen markieren", systemImage: "circle")
            }
        }
    }

    // MARK: - Bild

    /// Breite des Standbildes, gemessen an der Karte.
    ///
    /// Nicht fest: auf einem iPhone SE wäre die Vorlagenbreite die halbe
    /// Karte, auf dem iPad eine Briefmarke. Der Deckel oben hält das Bild
    /// davon ab, auf breiten Geräten die Karte zu beherrschen.
    private var thumbWidth: CGFloat {
        let card = width - NoriSpacing.screen * 2 - 20
        return min(max(card * 0.34, 104), 176)
    }

    private var thumbHeight: CGFloat { (thumbWidth * 9 / 16).rounded() }

    private func thumb(complete: Bool, ratio: Double) -> some View {
        ZStack {
            if let still = info?.stillURL {
                // image.tmdb.org braucht keine Kopfzeilen; `NoriCoverImage`
                // bringt aber den Zwischenspeicher mit, den `AsyncImage` nicht
                // hat — beim Blättern wird dieselbe Folge nicht neu geladen.
                NoriCoverImage(url: still, referer: "") { placeholder }
            } else {
                placeholder
            }

            if complete {
                Color.black.opacity(0.45)
            }

            if highlighted, !complete {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(NoriTheme.bg)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.9)))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
        }
        .frame(width: thumbWidth, height: thumbHeight)
        .overlay(alignment: .bottom) {
            // Der angefangene Teil als Streifen am unteren Bildrand — dort,
            // wo ihn jede Videoanwendung zeigt. Der Ring rechts sagt dasselbe
            // noch einmal, aber aus der Entfernung sieht man den Streifen.
            if ratio > 0, !complete {
                GeometryReader { geo in
                    Rectangle()
                        .fill(tone ?? NoriTheme.accent)
                        .frame(width: geo.size.width * min(max(ratio, 0), 1))
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }
                .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SeriesMetrics.thumb, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SeriesMetrics.thumb, style: .continuous)
                .strokeBorder(.white.opacity(0.07))
        }
    }

    /// Was steht, solange oder falls es kein Standbild gibt.
    ///
    /// Zuerst das Artwork der Serie, stark abgedunkelt: das ist kein Bild
    /// dieser Folge, soll also auch nicht so aussehen, füllt die Kachel aber
    /// mit etwas, das zur Serie gehört. Ohne jedes Artwork bleibt Noris
    /// eigener Rückfall — ein leeres dunkles Rechteck sähe aus wie ein
    /// Ladefehler.
    @ViewBuilder
    private var placeholder: some View {
        if let url = artwork.url {
            ZStack {
                NoriCoverImage(url: url, referer: artwork.referer) { SeriesThumbFallback(number: episode.number) }
                    .blur(radius: 8, opaque: true)
                    .brightness(-0.34)
                    .saturation(0.6)
                SeriesThumbFallback(number: episode.number).opacity(0.62)
            }
        } else {
            SeriesThumbFallback(number: episode.number)
        }
    }

    // MARK: - Text

    private var title: some View {
        (
            Text("\(episode.number).")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
                + Text("  ")
                + Text(shownTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NoriTheme.fg)
        )
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// „Episode 7" ist kein Titel, sondern die Nummer in Worten. Beide Quellen
    /// setzen das ein, wo sie keinen echten Titel haben.
    private static func isPlaceholder(_ text: String) -> Bool {
        text.range(
            of: #"^\s*(episode|folge|film|ep\.?)\s*\d+\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Der Titel der Quelle, sofern es einer ist; sonst der von TMDB, sonst
    /// die Nummer.
    private var shownTitle: String {
        let own = episode.germanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty, !Self.isPlaceholder(own) { return own }
        if let other = info?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !other.isEmpty, !Self.isPlaceholder(other) {
            return other
        }
        let english = episode.englishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !english.isEmpty, !Self.isPlaceholder(english) { return english }
        if !own.isEmpty { return own }
        return season == "filme" ? "Film \(episode.number)" : "Folge \(episode.number)"
    }

    /// „24. März 2024 · 24 Min. · GerDub / GerSub". Fehlt ein Teil, fehlt auch
    /// sein Trenner; erfunden wird nichts.
    private var meta: String? {
        var parts: [String] = []
        if let date = airDate {
            parts.append(date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "de_DE"))))
        }
        if let minutes = info?.runtime { parts.append("\(minutes) Min.") }
        // Nur die erste Sprache. „GerDub/GerSub" hinter Datum und Laufzeit
        // passt auf einem iPhone nicht mehr in die Zeile, und eine auf
        // „GerS…" abgeschnittene Sprachangabe ist keine. Die vollständige
        // Liste steht in der Vorlesefassung und in der Auswahl des Players.
        if let language = episode.languages.first.map(Self.languageLabel) { parts.append(language) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// TMDB liefert „2024-03-24". Zerlegt statt über einen `DateFormatter`:
    /// den bräuchte es sonst als geteilten Zustand, und der Kern bringt die
    /// Umrechnung schon mit.
    private var airDate: Date? {
        let parts = (info?.airDate ?? "").split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[1] > 0, parts[2] > 0 else { return nil }
        return berlinDate(year: parts[0], month: parts[1], day: parts[2], hour: 12)
    }

    /// Die Quellen führen Deutsch als „DE"; die Einstellungen nennen dasselbe
    /// „GerDub". Zwei Namen für eine Sache verwirren mehr, als sie sagen.
    private static func languageLabel(_ raw: String) -> String {
        raw == "DE" ? "GerDub" : raw
    }

    private func accessibleLabel(complete: Bool, ratio: Double) -> String {
        var text = "Folge \(episode.number), \(shownTitle)"
        if let meta { text += ", \(meta)" }
        if episode.languages.count > 1 {
            text += ", weitere Sprachen: " + episode.languages.dropFirst().map(Self.languageLabel).joined(separator: ", ")
        }
        if complete {
            text += ", gesehen"
        } else if ratio > 0 {
            text += ", zu \(Int(ratio * 100)) Prozent gesehen"
        }
        return text
    }
}

// MARK: - Fortschritt

/// Der Ring rechts auf jeder Folge.
///
/// Drei Zustände, und zwar in dieser Reihenfolge unterscheidbar: ein leerer
/// Ring heißt ungesehen, ein angefangener Bogen heißt angefangen, eine
/// gefüllte Scheibe mit Haken heißt fertig. Der Haken ist bewusst eine Form
/// und nicht nur eine andere Farbe — Farbe allein ist keine Auskunft.
struct SeriesProgressRing: View {
    let ratio: Double
    let complete: Bool
    let tone: Color?

    private var accent: Color { tone ?? NoriTheme.accent }

    private let size: CGFloat = 32

    var body: some View {
        ZStack {
            if complete {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(NoriTheme.bg)
            } else {
                Circle()
                    .strokeBorder(NoriTheme.muted.opacity(0.45), lineWidth: 2.5)
                if ratio > 0 {
                    Circle()
                        .trim(from: 0, to: min(max(ratio, 0.03), 1))
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.25)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Rückfall

/// Was auf einer Folgenkachel steht, wenn es weder Standbild noch Artwork
/// gibt: die Nummer und ein Filmstreifen. Ein leeres Rechteck sähe aus wie
/// ein Fehler, dabei fehlt hier nichts, was da sein müsste.
struct SeriesThumbFallback: View {
    let number: Int

    var body: some View {
        ZStack {
            NoriTheme.elevated
            VStack(spacing: 3) {
                Image(systemName: "film")
                    .font(.system(size: 16))
                Text("\(number)")
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(NoriTheme.fg.opacity(0.3))
        }
    }
}
