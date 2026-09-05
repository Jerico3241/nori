import SwiftUI

struct SeriesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerHost.self) private var playerHost
    @Environment(CatalogStore.self) private var catalogStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let slug: String
    let titleHint: String
    var providerOverride: CatalogProvider? = nil

    @State private var detail: SeriesDetail?
    @State private var season: String = "1"
    @State private var error: String?
    @State private var loading = true
    @State private var coverColor = NoriTheme.accent
    @State private var pickingCover = false
    @State private var details = CoverDetails()

    var body: some View {
        // Der Kopfbereich bringt sein eigenes Bild mit und läuft über die volle
        // Breite, deshalb hier nur noch der Grundhintergrund.
        ZStack(alignment: .top) {
            NoriTheme.bg
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .foregroundStyle(NoriTheme.fg)
        }
        .navigationTitle(detail?.title ?? titleHint)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    library.toggleFavorite(slug, title: detail?.title ?? titleHint)
                } label: {
                    Label(
                        library.isFavorite(slug) ? "Gemerkt" : "Merken",
                        systemImage: library.isFavorite(slug) ? "heart.fill" : "heart"
                    )
                    .contentTransition(.symbolEffect(.replace))
                }
                .help(library.isFavorite(slug) ? "Aus Merkliste entfernen" : "Zur Merkliste hinzufügen")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    pickingCover = true
                } label: {
                    Label("Cover wählen", systemImage: "photo")
                }
                .help("Cover manuell auswählen, wenn das automatische nicht passt")
            }
        }
        .task { await load(season: nil) }
        .task(id: detail?.coverPath) {
            guard let url = AniworldClient.coverURL(detail?.coverPath, provider: library.provider) else { return }
            // Das Cover der Quelle festhalten, damit es überall als
            // Rückfallebene bereitsteht, wenn TMDB nichts findet.
            await CoverIndex.shared.rememberSource(slug: slug, url: url)
            if let tone = await CoverToneSampler.sample(url: url) { coverColor = tone }
        }
        .task(id: detail?.title) {
            guard let loaded = detail else { return }
            details = await CoverIndex.shared.detailsLoading(
                slug: slug,
                title: loaded.title,
                kind: providerOverride ?? library.provider
            )
        }
        .sheet(isPresented: $pickingCover) {
            CoverPicker(
                slug: slug,
                title: detail?.title ?? titleHint,
                kind: providerOverride ?? library.provider,
                sourceCover: AniworldClient.coverURL(detail?.coverPath, provider: providerOverride ?? library.provider)
            )
        }
    }

    private var subtitle: String {
        guard let detail else { return "" }
        var parts: [String] = []
        if let year = detail.yearStart, !year.isEmpty { parts.append(year) }
        if !detail.genres.isEmpty { parts.append(detail.genres.prefix(3).joined(separator: " · ")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var content: some View {
        if loading && detail == nil {
            ProgressView("Serie wird geladen")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, detail == nil {
            ContentUnavailableView(
                "Nicht geladen",
                systemImage: "wifi.exclamationmark",
                description: Text(error)
            )
        } else if let detail {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    header(detail)
                    facts(detail)
                    episodes(detail)
                    similar(detail)
                }
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Hintergrund des Kopfbereichs: Breitbild oder, wenn keines da ist, ein
    /// Verlauf aus der Coverfarbe. Darüber zwei Abdunklungen, damit die Schrift
    /// auf jedem Bild lesbar bleibt.
    @ViewBuilder
    private var headerBackground: some View {
        ZStack {
            if let wide = details.backdrop {
                AsyncImage(url: wide) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        NoriTheme.elevated
                    }
                }
            } else {
                LinearGradient(
                    colors: [coverColor.opacity(0.55), NoriTheme.bg],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: coverColor)
            }

            LinearGradient(
                colors: [.black.opacity(0.9), .black.opacity(0.5), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            LinearGradient(
                colors: [.clear, .black.opacity(0.85)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }

    /// Der Kopfbereich wächst mit seinem Inhalt und hat nur eine **Mindest**höhe.
    ///
    /// Vorher stand hier `.frame(height: 430)` mit `.clipped()`. Ist der Inhalt
    /// höher als 430 pt — langer Titel, viele Chips, Staffelauswahl — zentriert
    /// SwiftUI ihn in diesem Rahmen, und `.clipped()` schneidet oben und unten
    /// ab: der Abspielen-Knopf war zur Hälfte weg. Jetzt bestimmt der Inhalt die
    /// Höhe, der Hintergrund liegt dahinter, und geschnitten wird nur noch das,
    /// was das Breitbild über den Rand hinaus malt.
    private func header(_ detail: SeriesDetail) -> some View {
        HStack(alignment: .bottom, spacing: 22) {
            PosterTile(
                title: detail.title,
                slug: detail.slug,
                coverURL: AniworldClient.coverURL(detail.coverPath, provider: library.provider)
            )
            .frame(width: 168)
            .contextMenu {
                Button("Cover wählen…") { pickingCover = true }
            }
            .help("Rechtsklick, um das Cover manuell zu wählen")

            VStack(alignment: .leading, spacing: 11) {
                Text(detail.title)
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 2)

                HStack(spacing: 8) {
                    ForEach(metaChips(detail), id: \.self) { chip in
                        Text(chip)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.16), in: Capsule())
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }

                // Nur die Bewertung. Quelle und Genres standen hier vorher
                // ein zweites Mal — sie stehen in der Faktenspalte unter
                // der Beschreibung, und die Quelle zusätzlich in der
                // Seitenleiste.
                if let stars = details.stars {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(0 ..< 5, id: \.self) { i in
                                Image(systemName: Double(i) + 0.5 < stars ? "star.fill" : "star")
                                    .font(.caption2)
                            }
                        }
                        .foregroundStyle(NoriTheme.accent)
                        Text(String(format: "%.1f", stars))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                let stats = library.seasonStats(slug: slug, season: season, episodes: detail.episodes)
                if stats.total > 0 {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(stats.watched), total: Double(stats.total))
                            .frame(width: 170)
                            .tint(NoriTheme.accent)
                        Text("\(stats.pct) % · \(stats.watched)/\(stats.total) Folgen")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }

                HStack(spacing: 10) {
                    let target = library.nextPlay(slug: slug, season: season, episodes: detail.episodes)
                    Button {
                        guard let ep = detail.episodes.first(where: { $0.number == target.episode }) else { return }
                        open(series: detail, episode: ep, resumeAt: library.resumeEnabled ? target.resumeAt : 0)
                    } label: {
                        Label(cta(target.kind, episode: target.episode), systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(NoriTheme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .foregroundStyle(NoriTheme.onAccent)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)

                    BookmarkButton(slug: slug, title: detail.title, large: true)

                    if detail.seasons.count > 1 {
                        Picker("Staffel", selection: seasonBinding) {
                            ForEach(detail.seasons) { item in
                                Text(item.label).tag(item.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 170)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, NoriLayout.gutter)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 430, alignment: .bottomLeading)
        .background { headerBackground }
        .clipped()
    }

    /// Beschreibung links, harte Fakten rechts.
    @ViewBuilder
    private func facts(_ detail: SeriesDetail) -> some View {
        let text = detail.description.isEmpty ? (details.overview ?? "") : detail.description
        if !text.isEmpty || !detail.genres.isEmpty {
            HStack(alignment: .top, spacing: 40) {
                if !text.isEmpty {
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(NoriTheme.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: 620, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !detail.genres.isEmpty {
                        factRow("Genres", detail.genres.joined(separator: ", "))
                    }
                    let langs = uniqueLanguages(detail)
                    if !langs.isEmpty {
                        factRow("Sprachen", langs.joined(separator: ", "))
                    }
                    factRow("Quelle", library.provider.label)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, NoriLayout.gutter)
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NoriTheme.fg)
            Text(value)
                .font(.caption)
                .foregroundStyle(NoriTheme.muted)
        }
    }

    private func uniqueLanguages(_ detail: SeriesDetail) -> [String] {
        var seen: [String] = []
        for episode in detail.episodes {
            for lang in episode.languages where !seen.contains(lang) {
                seen.append(lang)
            }
        }
        return seen
    }

    /// Empfehlungen aus dem geladenen Katalog nach Genre-Überschneidung. Damit
    /// führt jeder Vorschlag garantiert auf einen Titel, den die Quelle auch
    /// wirklich hat.
    @ViewBuilder
    private func similar(_ detail: SeriesDetail) -> some View {
        let items = catalogStore.similar(to: slug, genres: detail.genres)
        if !items.isEmpty {
            PosterRow(title: "Ähnliche Titel", items: items)
        }
    }

    private func metaChips(_ detail: SeriesDetail) -> [String] {
        var chips: [String] = []
        if let fsk = detail.fsk, !fsk.isEmpty { chips.append("FSK \(fsk)") }
        if let start = detail.yearStart, !start.isEmpty {
            if let end = detail.yearEnd, !end.isEmpty, end != start {
                chips.append("\(start)–\(end)")
            } else {
                chips.append(start)
            }
        }
        // Genres stehen bewusst nicht hier: die Faktenspalte unter der
        // Beschreibung zeigt sie vollständig, statt hier die ersten drei.
        return chips
    }

    private var seasonBinding: Binding<String> {
        Binding(
            get: { season },
            set: { next in
                guard next != season else { return }
                season = next
                Task { await load(season: next) }
            }
        )
    }

    private func episodes(_ detail: SeriesDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NoriSectionHeader("Folgen", trailing: "\(detail.episodes.count)")
            VStack(spacing: 0) {
                ForEach(Array(detail.episodes.enumerated()), id: \.element.id) { index, ep in
                    if index > 0 { Divider().padding(.leading, 62) }
                    EpisodeRow(series: detail, episode: ep, season: season) { resumeAt in
                        open(series: detail, episode: ep, resumeAt: resumeAt)
                    }
                }
            }
            .background(NoriTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
        }
        .frame(maxWidth: 980, alignment: .leading)
        .padding(.horizontal, NoriLayout.gutter)
    }

    private func open(series: SeriesDetail, episode: Episode, resumeAt: Double) {
        playerHost.request = PlayerRequest(
            series: series,
            episode: episode,
            season: season,
            resumeAt: resumeAt
        )
        openWindow(id: NoriWindow.player)
    }

    func cta(_ kind: String, episode: Int) -> String {
        switch kind {
        case "resume": return "Weiterschauen · Folge \(episode)"
        case "next": return "Weiter · Folge \(episode)"
        default: return "Abspielen · Folge \(episode)"
        }
    }

    func load(season: String?) async {
        loading = detail == nil
        error = nil
        let first = providerOverride ?? library.provider
        do {
            let loaded = try await AniworldClient.shared.getSeries(provider: first, slug: slug, season: season)
            if library.provider != first { library.provider = first }
            detail = loaded
            self.season = loaded.activeSeason
            library.remember(slug: slug, title: loaded.title, provider: first)
        } catch let firstError {
            // Die andere Quelle nur probieren, wenn der Aufrufer keine genannt
            // hat. Mit ausdrücklich übergebener Quelle — Kalender, Merkliste,
            // Weiterschauen — stellte ein einmaliger Fehler sonst die ganze App
            // auf die falsche Quelle um, und der nächste Aufruf landete auf
            // einer Seite, die es dort nicht gibt.
            if providerOverride != nil {
                self.error = firstError.localizedDescription
            } else {
                let other: CatalogProvider = first == .aniworld ? .serienstream : .aniworld
                do {
                    let loaded = try await AniworldClient.shared.getSeries(provider: other, slug: slug, season: season)
                    library.provider = other
                    detail = loaded
                    self.season = loaded.activeSeason
                    library.remember(slug: slug, title: loaded.title, provider: other)
                } catch {
                    self.error = firstError.localizedDescription
                }
            }
        }
        loading = false
    }
}

/// Manuelle Cover-Zuordnung. TMDB findet nicht immer den richtigen Titel —
/// besonders bei Anime mit mehreren Staffeln unter ähnlichem Namen. Hier lässt
/// sich das Cover der Quelle oder ein anderer TMDB-Treffer festlegen.
struct CoverPicker: View {
    @Environment(\.dismiss) private var dismiss

    let slug: String
    let title: String
    let kind: CatalogProvider
    let sourceCover: URL?

    @State private var candidates: [CoverCandidate] = []
    @State private var current: URL?
    @State private var loading = true

    private let grid = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cover wählen")
                        .font(.headline)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(NoriTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let sourceCover {
                        section("Von \(kind.label)") {
                            option(url: sourceCover, label: "Cover der Quelle")
                        }
                    }

                    if loading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("TMDB wird durchsucht…")
                                .font(.caption)
                                .foregroundStyle(NoriTheme.muted)
                        }
                    } else if !CoverIndex.shared.hasKey {
                        // Ohne Schlüssel fragt Nori TMDB gar nicht erst an. Das
                        // sähe sonst wie „keine Treffer" aus, obwohl gar nicht
                        // gesucht wurde.
                        Text("Ohne TMDB-Schlüssel gibt es hier nichts zur Auswahl. Einen Schlüssel trägt man unter Einstellungen › Daten ein.")
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                    } else if candidates.isEmpty {
                        Text("TMDB liefert für diesen Titel keine Treffer.")
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                    } else {
                        section("Von TMDB") {
                            LazyVGrid(columns: grid, alignment: .leading, spacing: 14) {
                                ForEach(candidates) { candidate in
                                    option(url: candidate.url, label: candidate.label)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Button("Automatisch") {
                    Task { await choose(nil) }
                }
                .disabled(current == nil)
                .help("Manuelle Auswahl verwerfen und wieder automatisch zuordnen")
                Spacer()
                if current != nil {
                    Label("Manuell gesetzt", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(NoriTheme.accent)
                }
            }
            .padding(16)
        }
        .frame(width: 640, height: 540)
        .background(NoriTheme.bg)
        .task {
            current = await CoverIndex.shared.override(for: slug)
            candidates = await CoverIndex.shared.candidates(title: title, kind: kind)
            loading = false
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func option(url: URL, label: String) -> some View {
        let selected = current == url
        return Button {
            Task { await choose(url) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        NoriTheme.elevated.overlay {
                            Image(systemName: "photo").foregroundStyle(NoriTheme.muted)
                        }
                    default:
                        NoriTheme.elevated.overlay { ProgressView().controlSize(.small) }
                    }
                }
                .frame(width: 110, height: 165)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? NoriTheme.accent : NoriTheme.border, lineWidth: selected ? 2.5 : 1)
                }
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(selected ? NoriTheme.fg : NoriTheme.muted)
                    .lineLimit(2, reservesSpace: true)
                    .frame(width: 110, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .help(label)
    }

    private func choose(_ url: URL?) async {
        await CoverIndex.shared.setOverride(slug: slug, url: url)
        current = url
        NotificationCenter.default.post(name: .noriCoverChanged, object: slug)
    }
}

struct EpisodeRow: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let series: SeriesDetail
    let episode: Episode
    let season: String
    let play: (Double) -> Void

    @State private var hovering = false

    var body: some View {
        let item = library.progress(slug: series.slug, season: season, episode: episode.number, path: episode.path, provider: library.provider)
        let complete = isEpisodeComplete(item)
        let ratio = watchRatio(item)
        let resumeAt = library.resumeEnabled ? resumePosition(item) : 0

        Button {
            play(resumeAt)
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(NoriTheme.elevated)
                        .frame(width: 38, height: 38)
                    if hovering {
                        Image(systemName: "play.fill")
                            .foregroundStyle(NoriTheme.accent)
                    } else if complete {
                        Image(systemName: "checkmark")
                            .foregroundStyle(NoriTheme.muted)
                    } else {
                        Text("\(episode.number)")
                            .font(.callout.weight(.medium).monospacedDigit())
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(episode.germanTitle.isEmpty ? "Folge \(episode.number)" : episode.germanTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if !episode.englishTitle.isEmpty {
                        Text(episode.englishTitle)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(1)
                    }
                    if ratio > 0, !complete {
                        ProgressView(value: ratio)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .frame(maxWidth: 220)
                    }
                }

                Spacer(minLength: 8)

                if !episode.languages.isEmpty {
                    Text(episode.languages.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                }
                if let item, !complete, item.positionSec >= 8 {
                    Text("\(Int(ratio * 100)) %")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(NoriTheme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(hovering ? NoriTheme.hover : Color.clear)
        }
        .buttonStyle(NoriPressStyle(enabled: !reduceMotion))
        .onHover { hovering = $0 }
        .help(episode.germanTitle.isEmpty ? "Folge \(episode.number)" : episode.germanTitle)
        .contextMenu {
            Button("Abspielen") { play(resumeAt) }
            if resumeAt >= 8 {
                Button("Von vorne abspielen") { play(0) }
            }
        }
    }
}
