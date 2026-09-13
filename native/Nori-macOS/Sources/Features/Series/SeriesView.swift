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
    /// Standbilder und Beschreibungen der Folgen, nach Nummer.
    @State private var episodeInfo: [Int: EpisodeInfo] = [:]
    @State private var similarItems: [CatalogItem] = []

    /// Läuft neu, sobald die Staffel wechselt **oder** die Serie eintrifft:
    /// beim ersten Aufbau steht die Staffel schon auf „1", `detail` aber noch
    /// nicht — ein Schlüssel nur aus der Staffel würde das verpassen.
    private var episodeTaskID: String { "\(slug)|\(season)|\(detail == nil ? 0 : 1)" }

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
            guard let url = AniworldClient.coverURL(detail?.coverPath, provider: providerOverride ?? library.provider) else { return }
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
                // Ohne die Alternativtitel sucht TMDB nur unter dem Namen,
                // unter dem die Quelle die Serie führt — bei Anime
                // regelmäßig einer, den TMDB gar nicht kennt.
                alternates: loaded.alts,
                kind: providerOverride ?? library.provider
            )
        }
        .task(id: episodeTaskID) {
            guard let loaded = detail else { return }
            // Erst das, was schon dasteht: die Liste erscheint mit Bildern,
            // ohne auf TMDB zu warten. Der Aufruf trägt danach nach.
            episodeInfo = await EpisodeIndex.shared.cached(slug: slug, season: season)
            let fetched = await EpisodeIndex.shared.load(
                slug: slug,
                title: loaded.title,
                // Die Quelle führt Serien oft unter einem eingedeutschten oder
                // verkürzten Namen, den TMDB nicht kennt. Die Alternativtitel
                // von der Detailseite treffen dann meist.
                alternates: loaded.alts,
                season: season,
                kind: providerOverride ?? library.provider,
                // Die Folgen der Quelle als Anker: TMDB teilt Anime oft
                // anders in Staffeln ein, und dann trifft die bloße Nummer
                // die falsche Folge oder gar keine.
                sourceEpisodes: loaded.episodes.tmdbSourceEpisodes
            )
            guard !Task.isCancelled, !fetched.isEmpty else { return }
            episodeInfo = fetched
        }
        .task(id: "\(detail?.slug ?? "")|\(detail?.genres.joined(separator: ",") ?? "")|\(catalogStore.revision)") {
            guard let loaded = detail else {
                similarItems = []
                return
            }
            let items = catalogStore.items
            let provider = providerOverride ?? library.provider
            let found = await Task.detached(priority: .utility) {
                CatalogStore.similar(in: items, to: loaded.slug, genres: loaded.genres, provider: provider)
            }.value
            guard !Task.isCancelled else { return }
            similarItems = found
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
            SeriesSkeleton(title: titleHint)
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
                // Über den gemeinsamen Bildlader statt `AsyncImage`: der hält
                // das Breitbild im Zwischenspeicher, und die Seite lädt es beim
                // zweiten Öffnen nicht erneut.
                NoriCoverImage(url: wide, referer: "https://www.themoviedb.org/") {
                    NoriTheme.elevated
                }
            } else {
                LinearGradient(
                    colors: [coverColor.opacity(0.55), NoriTheme.bg],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                .animation(NoriMotion.allowed(NoriMotion.content, reduceMotion: reduceMotion), value: coverColor)
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
                coverURL: AniworldClient.coverURL(detail.coverPath, provider: providerOverride ?? library.provider)
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

                // Zweizeilig, wenn die Zeile nicht passt. In einem schmalen
                // Fenster brach „Abspielen · Folge 1" sonst mitten im Knopf um,
                // und von der Staffelauswahl blieb „Staff…".
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        playButton(detail)
                        BookmarkButton(slug: slug, title: detail.title, large: true)
                        seasonPicker(detail)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            playButton(detail)
                            BookmarkButton(slug: slug, title: detail.title, large: true)
                        }
                        seasonPicker(detail)
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

    private func playButton(_ detail: SeriesDetail) -> some View {
        let target = library.nextPlay(slug: slug, season: season, episodes: detail.episodes)
        return Button {
            guard let ep = detail.episodes.first(where: { $0.number == target.episode }) else { return }
            open(series: detail, episode: ep, resumeAt: library.resumeEnabled ? target.resumeAt : 0)
        } label: {
            Label(cta(target.kind, episode: target.episode), systemImage: "play.fill")
                .font(.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(NoriTheme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(NoriTheme.onAccent)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }

    @ViewBuilder
    private func seasonPicker(_ detail: SeriesDetail) -> some View {
        if detail.seasons.count > 1 {
            Picker("Staffel", selection: seasonBinding) {
                ForEach(detail.seasons) { item in
                    Text(item.label).tag(item.id)
                }
            }
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: 170, alignment: .leading)
        }
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
                    factRow("Quelle", (providerOverride ?? library.provider).label)
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
    ///
    /// Gerechnet einmal je Serie und Katalogstand (siehe die Aufgabe dazu),
    /// nicht in `body` — die Seite zeichnet bei jedem Laden eines
    /// Standbilds neu, und jedes Mal lief ein Durchgang über den Katalog.
    @ViewBuilder
    private func similar(_ detail: SeriesDetail) -> some View {
        if !similarItems.isEmpty {
            PosterRow(title: "Ähnliche Titel", items: similarItems)
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
                    // Die Trennlinie beginnt hinter der Kachel, nicht hinter
                    // dem alten 38er-Quadrat.
                    if index > 0 { Divider().padding(.leading, 154) }
                    EpisodeRow(
                        series: detail,
                        episode: ep,
                        season: season,
                        info: episodeInfo[ep.number]
                    ) { resumeAt in
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
            resumeAt: resumeAt,
            provider: providerOverride ?? library.provider
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
    /// Bild und Beschreibung aus TMDB. `nil`, solange nichts geladen ist oder
    /// TMDB die Serie nicht kennt — dann sieht die Zeile aus wie zuvor, nur
    /// mit einer Kachel im 16:9-Format statt eines Quadrats.
    var info: EpisodeInfo? = nil
    let play: (Double) -> Void

    @State private var hovering = false

    /// „Episode 7" ist kein Titel, sondern die Nummer in Worten. Beide Quellen
    /// setzen das ein, wo sie keinen echten Titel haben — und daneben steht
    /// dann noch einmal dasselbe als englischer Titel.
    private static func isPlaceholder(_ text: String) -> Bool {
        text.range(
            of: #"^\s*(episode|folge|ep\.?)\s*\d+\s*$"#,
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
        if !own.isEmpty { return own }
        return "Folge \(episode.number)"
    }

    /// Der englische Titel, aber nur wenn er etwas hinzufügt: dieselbe
    /// Zeichenkette zweimal untereinander ist keine Auskunft.
    private var shownSubtitle: String? {
        let other = episode.englishTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !other.isEmpty, !Self.isPlaceholder(other) else { return nil }
        guard other.caseInsensitiveCompare(shownTitle) != .orderedSame else { return nil }
        return other
    }

    /// Der Tooltip trägt auf dem Mac, was in der Zeile nicht hinpasst. Die
    /// Beschreibung wird in der Liste auf zwei Zeilen gekürzt — hier steht
    /// sie vollständig, ohne dass dafür Platz nötig wäre.
    private var tooltip: String {
        var parts = [shownTitle]
        if let text = info?.overview, !text.isEmpty { parts.append(text) }
        return parts.joined(separator: "\n\n")
    }

    var body: some View {
        let item = library.progress(slug: series.slug, season: season, episode: episode.number, path: episode.path, provider: library.provider)
        let complete = isEpisodeComplete(item)
        let ratio = watchRatio(item)
        let resumeAt = library.resumeEnabled ? resumePosition(item) : 0

        Button {
            play(resumeAt)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                thumb(complete: complete, ratio: ratio)

                VStack(alignment: .leading, spacing: 3) {
                    Text(shownTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if let shownSubtitle {
                        Text(shownSubtitle)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(1)
                    }
                    if let text = info?.overview, !text.isEmpty {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(NoriTheme.muted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
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
        .help(tooltip)
        .contextMenu {
            Button("Abspielen") { play(resumeAt) }
            if resumeAt >= 8 {
                Button("Von vorne abspielen") { play(0) }
            }
        }
    }

    /// Die Folgenkachel: das Standbild aus TMDB, sonst die Nummer wie bisher.
    ///
    /// Breiter als auf dem iPhone (128 statt 112 Punkte) — die Fensterbreite
    /// gibt es her, und eine briefmarkengroße Kachel wäre auf dem Mac keine
    /// Auskunft. Der Fortschritt liegt als schmaler Streifen am unteren
    /// Bildrand statt als Balken unter dem Titel, wo er der Beschreibung im
    /// Weg stünde.
    private func thumb(complete: Bool, ratio: Double) -> some View {
        ZStack {
            NoriTheme.elevated
            if let url = info?.stillURL {
                // image.tmdb.org braucht keine Kopfzeilen; `NoriCoverImage`
                // bringt aber den Zwischenspeicher mit, den `AsyncImage` nicht
                // hat — dieselbe Folge wird beim Blättern nicht neu geladen.
                NoriCoverImage(url: url, referer: "https://www.themoviedb.org/") {
                    Color.clear
                }
            }
            if hovering {
                Color.black.opacity(info?.stillURL == nil ? 0 : 0.45)
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(NoriTheme.accent)
            } else if complete {
                Color.black.opacity(info?.stillURL == nil ? 0 : 0.45)
                Image(systemName: "checkmark")
                    .foregroundStyle(NoriTheme.muted)
            } else if info?.stillURL == nil {
                Text("\(episode.number)")
                    .font(.callout.weight(.medium).monospacedDigit())
            }
        }
        .overlay(alignment: .bottomLeading) {
            if info?.stillURL != nil, !complete, !hovering {
                Text("\(episode.number)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(5)
            }
        }
        .overlay(alignment: .bottom) {
            if ratio > 0, !complete {
                GeometryReader { geo in
                    Rectangle()
                        .fill(NoriTheme.accent)
                        .frame(width: geo.size.width * min(max(ratio, 0), 1), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 3)
            }
        }
        .frame(width: 128, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(NoriTheme.border)
        }
    }
}


/// Die Detailseite, bevor die Serie da ist.
///
/// Kopfbereich mit Poster und Titel in denselben Maßen wie `header`, darunter
/// der Platz der Beschreibung und der Folgenliste. Der Titel kam mit dem Klick
/// und steht deshalb echt da statt als Balken.
///
/// Die Beschreibung fehlte hier vorher: beim Eintreffen der Serie schob sie
/// sich zwischen Kopfbereich und Folgen, und die Liste sprang um ihre Höhe
/// nach unten.
private struct SeriesSkeleton: View {
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .bottom, spacing: 22) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NoriTheme.elevated)
                        .aspectRatio(2 / 3, contentMode: .fit)
                        .frame(width: 168)
                    VStack(alignment: .leading, spacing: 11) {
                        Text(title)
                            .font(.system(size: 38, weight: .heavy))
                            .foregroundStyle(NoriTheme.fg)
                            .lineLimit(2)
                        Group {
                            Text("FSK 12 · 2024")
                                .font(.caption)
                            Text("Abspielen · Folge 1")
                                .font(.headline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 11)
                        }
                        .redacted(reason: .placeholder)
                        .foregroundStyle(NoriTheme.muted.opacity(0.4))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NoriLayout.gutter)
                .padding(.top, 34)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 430, alignment: .bottomLeading)
                .background {
                    LinearGradient(colors: [NoriTheme.elevated, NoriTheme.bg], startPoint: .top, endPoint: .bottom)
                }

                Text("Eine Beschreibung über drei Zeilen, damit ihr Platz schon steht, bevor die Serie eingetroffen ist und der Text erscheint.")
                    .font(.callout)
                    .lineLimit(3, reservesSpace: true)
                    .redacted(reason: .placeholder)
                    .foregroundStyle(NoriTheme.muted.opacity(0.4))
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, NoriLayout.gutter)

                VStack(alignment: .leading, spacing: 10) {
                    NoriSectionHeader("Folgen")
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(NoriTheme.surface)
                        .frame(height: 450)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(NoriTheme.border)
                        }
                }
                .frame(maxWidth: 980, alignment: .leading)
                .padding(.horizontal, NoriLayout.gutter)
            }
        }
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) wird geladen")
    }
}
