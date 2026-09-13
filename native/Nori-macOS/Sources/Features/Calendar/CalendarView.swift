import SwiftUI

struct CalendarView: View {
    @Environment(LibraryStore.self) private var library
    // Der Kalender braucht den Katalog, um „K-Drama" überhaupt erkennen zu
    // können: ein `AiringEntry` trägt Slug und Quelle, aber keine Genres.
    @Environment(CatalogStore.self) private var catalogStore
    @State private var payload: CalendarPayload?
    @State private var error: String?
    @State private var loading = true
    // Der Kalender steht auf Liste: hier zählt, wann etwas kommt, und das
    // steht in der Zeile. Katalog und Merkliste starten dagegen auf Raster.
    @AppStorage("nori.calendar.layout") private var layoutRaw = NoriViewMode.list.rawValue

    private var layout: NoriViewMode { NoriViewMode(rawValue: layoutRaw) ?? .list }
    private let grid = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 18)]

    var body: some View {
        Group {
            if loading && payload == nil {
                // Zeilen im Umriss statt eines Rädchens mitten im Fenster.
                ScrollView {
                    NoriSkeletonGroup(label: "Kalender wird geladen") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(0 ..< 12, id: \.self) { _ in
                                NoriRowSkeleton()
                                    .padding(.horizontal, 20)
                                Divider()
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
                .scrollDisabled(true)
            } else if let error, payload == nil {
                ContentUnavailableView(
                    "Kalender nicht geladen",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(error)
                )
            } else if let payload {
                if layout == .grid {
                    gridBody(payload)
                } else {
                    listBody(payload)
                }
            }
        }
        .navigationTitle("Kalender")
        .navigationSubtitle(library.scope.label)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NoriViewModePicker(raw: $layoutRaw)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load(force: true) }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("Kalender neu laden (⌘R)")
                .disabled(loading)
            }
        }
        // Auch am Katalog aufgehängt: bei einem Bereich mit Genre entscheidet
        // er mit, was der Kalender zeigen darf. Lädt er nach dem Kalender
        // fertig, muss der Kalender noch einmal durch den Filter.
        .task(id: reloadKey) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .noriRefreshRequested)) { _ in
            Task { await load(force: true) }
        }
    }

    /// Wechselt, wenn sich der Bereich ändert — oder der Katalog, sofern der
    /// Bereich überhaupt an einem Genre hängt.
    private var reloadKey: String {
        guard library.scope.genre != nil else { return library.scope.rawValue }
        return "\(library.scope.rawValue)|\(catalogStore.revision)"
    }

    private func listBody(_ payload: CalendarPayload) -> some View {
        List {
            ForEach(grouped(payload.upcoming), id: \.label) { group in
                Section(group.label) {
                    ForEach(group.rows) { row in
                        NoriSeriesLink(slug: row.slug, titleHint: row.title, provider: row.provider ?? library.provider) {
                            CalendarRow(entry: row, provider: row.provider ?? library.provider)
                        }
                        .help(row.title)
                    }
                }
            }
            if !payload.recent.isEmpty {
                Section("Zuletzt") {
                    ForEach(payload.recent) { row in
                        NoriSeriesLink(slug: row.slug, titleHint: row.title, provider: row.provider ?? library.provider) {
                            CalendarRow(entry: row, provider: row.provider ?? library.provider)
                        }
                        .help(row.title)
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func gridBody(_ payload: CalendarPayload) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(grouped(payload.upcoming), id: \.label) { group in
                    section(group.label, rows: group.rows)
                }
                if !payload.recent.isEmpty {
                    section("Zuletzt", rows: payload.recent)
                }
            }
            .padding(20)
        }
        .background(NoriTheme.bg)
    }

    private func section(_ label: String, rows: [AiringEntry]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NoriSectionHeader(label, trailing: "\(rows.count)")
            LazyVGrid(columns: grid, alignment: .leading, spacing: 20) {
                ForEach(rows) { row in
                    let source = row.provider ?? library.provider
                    NoriPosterCell(
                        title: row.title,
                        slug: row.slug,
                        // Ohne Staffelangabe steht dort nur die Folgennummer —
                        // im Kalender ist gerade das die Auskunft.
                        subtitle: row.season.isEmpty ? "F\(row.episode)" : "S\(row.season) · F\(row.episode)",
                        coverURL: AniworldClient.coverURL(row.coverPath, provider: source),
                        kind: source
                    )
                }
            }
        }
    }

    func grouped(_ rows: [AiringEntry]) -> [(label: String, rows: [AiringEntry])] {
        var order: [String] = []
        var map: [String: [AiringEntry]] = [:]
        for row in rows {
            if map[row.dayLabel] == nil { order.append(row.dayLabel) }
            map[row.dayLabel, default: []].append(row)
        }
        return order.map { (label: $0, rows: map[$0] ?? []) }
    }

    func load(force: Bool = false) async {
        loading = payload == nil
        error = nil
        do {
            payload = try await Self.merged(
                scope: library.scope,
                slugs: catalogStore.slugs(for: library.scope),
                force: force
            )
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// Bei „Alle" beide Kalender, sonst nur den gewählten.
    ///
    /// Zusammengeführt wird über `HTML.packCalendar`, damit die Aufteilung in
    /// „kommend" und „kürzlich" dieselbe Regel benutzt wie bei einer einzelnen
    /// Quelle. Über die Kennung entdoppeln: dieselbe Folge kann bei beiden
    /// Seiten am selben Tag laufen.
    ///
    /// `slugs` schränkt zusätzlich ein, wenn der Bereich an einem Genre hängt.
    /// `nil` heißt „nicht einschränken" — nicht „nichts zeigen": solange der
    /// Katalog noch lädt, ist ein vollständiger Kalender die bessere Antwort
    /// als ein leerer.
    static func merged(
        scope: LibraryScope,
        slugs: Set<String>? = nil,
        force: Bool
    ) async throws -> CalendarPayload {
        let sources = scope.provider.map { [$0] } ?? CatalogProvider.allCases
        var all: [AiringEntry] = []
        var seen: Set<String> = []
        var failures: [Error] = []

        for source in sources {
            do {
                let payload = try await AniworldClient.shared.getCalendar(provider: source, force: force)
                for entry in payload.upcoming + payload.recent where !seen.contains(entry.id) {
                    if let slugs, !slugs.contains(entry.slug) { continue }
                    seen.insert(entry.id)
                    all.append(entry)
                }
            } catch {
                failures.append(error)
            }
        }

        // Nur melden, wenn nichts durchkam — eine leere Ansicht wäre bei einem
        // einseitigen Ausfall ein Rückschritt.
        if all.isEmpty, let first = failures.first { throw first }
        return HTML.packCalendar(all, now: Date())
    }
}

struct CalendarRow: View {
    let entry: AiringEntry
    var provider: CatalogProvider = .aniworld

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PosterTile(
                title: entry.title,
                slug: entry.slug,
                compact: true,
                coverURL: AniworldClient.coverURL(entry.coverPath, provider: provider),
                kind: provider
            )
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let english = entry.english, !english.isEmpty, english != entry.title {
                    Text(english)
                        .font(.caption)
                        .foregroundStyle(NoriTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if !entry.season.isEmpty {
                    Text("S\(entry.season) · F\(entry.episode)")
                        .monospacedDigit()
                }
                ForEach(entry.languages.prefix(3), id: \.self) { lang in
                    Text(lang)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NoriTheme.elevated, in: Capsule())
                }
            }
            .font(.caption)
            .foregroundStyle(NoriTheme.muted)
        }
        .padding(.vertical, 4)
    }
}
