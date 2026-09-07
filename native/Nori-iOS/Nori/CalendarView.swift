import SwiftUI

struct CalendarView: View {
    @Environment(LibraryStore.self) private var library
    /// Die zugelassenen Slugs, wenn der Bereich an einem Genre hängt.
    ///
    /// Ein `AiringEntry` trägt Slug und Quelle, aber keine Genres — ohne
    /// diesen Umweg zeigte „K-Drama" den vollständigen Serienstream-Kalender.
    let slugs: Set<String>?
    @State private var payload: CalendarPayload?
    @State private var error: String?
    @State private var loading = true
    // Der Kalender steht auf Liste: hier zählt, wann etwas kommt, und das
    // steht in der Zeile. Wer lieber Bilder sieht, schaltet um.
    @AppStorage("nori.layout.calendar") private var layout: NoriLayout = .list

    var body: some View {
        NoriScreen {
            Group {
                if loading && payload == nil {
                    ProgressView("Kalender wird geladen").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, payload == nil {
                    ContentUnavailableView("Kalender nicht geladen", systemImage: "calendar.badge.exclamationmark", description: Text(error))
                } else if let payload {
                    VStack(spacing: 0) {
                        LayoutBar(layout: $layout)
                        if layout == .grid {
                            grid(payload)
                        } else {
                            list(payload)
                        }
                    }
                }
            }
        }
        .navigationTitle("Kalender")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ScopeSwitch(scope: Bindable(library).scope)
            }
        }
        .task(id: reloadKey) { await load() }
        .refreshable { await load(force: true) }
    }

    private func list(_ payload: CalendarPayload) -> some View {
        List {
            ForEach(grouped(payload.upcoming), id: \.label) { group in
                Section(group.label) {
                    ForEach(group.rows) { row in
                        NoriSeriesLink(slug: row.slug, titleHint: row.title, provider: row.provider) {
                            CalendarRow(entry: row)
                        }
                        .listRowBackground(NoriTheme.surface)
                    }
                }
            }
            if !payload.recent.isEmpty {
                Section("Zuletzt") {
                    ForEach(payload.recent) { row in
                        NoriSeriesLink(slug: row.slug, titleHint: row.title, provider: row.provider) {
                            CalendarRow(entry: row)
                        }
                        .listRowBackground(NoriTheme.surface)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func grid(_ payload: CalendarPayload) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(grouped(payload.upcoming), id: \.label) { group in
                    NoriGridHeader(title: group.label)
                    section(group.rows)
                }
                if !payload.recent.isEmpty {
                    NoriGridHeader(title: "Zuletzt")
                    section(payload.recent)
                }
            }
            .padding(.vertical, 8)
            .padding(.bottom, 16)
        }
    }

    private func section(_ rows: [AiringEntry]) -> some View {
        LazyVGrid(columns: NoriLayout.columns, spacing: 18) {
            ForEach(rows) { row in
                let source = row.provider ?? library.provider
                NoriSeriesLink(
                    slug: row.slug,
                    titleHint: row.title,
                    scaleOnPress: true,
                    provider: row.provider
                ) {
                    NoriGridCard(
                        title: row.title,
                        slug: row.slug,
                        subtitle: row.season.isEmpty ? nil : "S\(row.season) · F\(row.episode)",
                        coverURL: AniworldClient.coverURL(row.coverPath, provider: source),
                        kind: source
                    )
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// Wechselt mit dem Bereich — und mit dem Katalog, sofern der Bereich
    /// überhaupt nach Genre einschränkt.
    private var reloadKey: String {
        guard library.scope.genre != nil else { return library.scope.rawValue }
        return "\(library.scope.rawValue)|\(slugs?.count ?? -1)"
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
                slugs: slugs,
                force: force
            )
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    /// Bei „Alle" beide Kalender, sonst nur den der zugehörigen Quelle.
    ///
    /// Zusammengeführt wird über `HTML.packCalendar`, damit die Aufteilung in
    /// „kommend" und „kürzlich" dieselbe Regel benutzt wie bei einer
    /// einzelnen Quelle. Über die Kennung entdoppeln: dieselbe Folge kann bei
    /// beiden Seiten am selben Tag laufen.
    ///
    /// `slugs` schränkt zusätzlich ein, wenn der Bereich an einem Genre
    /// hängt. `nil` heißt „nicht einschränken" — nicht „nichts zeigen":
    /// solange der Katalog noch lädt, ist ein vollständiger Kalender die
    /// bessere Antwort als ein leerer.
    static func merged(
        scope: LibraryScope,
        slugs: Set<String>? = nil,
        force: Bool
    ) async throws -> CalendarPayload {
        let sources = scope.provider.map { [$0] } ?? CatalogProvider.allCases
        var all: [AiringEntry] = []
        var seen: Set<String> = []
        var failures: [String] = []

        for source in sources {
            do {
                let payload = try await AniworldClient.shared.getCalendar(provider: source, force: force)
                for entry in payload.upcoming + payload.recent where !seen.contains(entry.id) {
                    if let slugs, !slugs.contains(entry.slug) { continue }
                    seen.insert(entry.id)
                    all.append(entry)
                }
            } catch {
                failures.append(error.localizedDescription)
            }
        }

        // Nur scheitern, wenn gar nichts kam. Eine ausgefallene Quelle darf
        // die andere nicht mitreißen.
        if all.isEmpty, !failures.isEmpty {
            throw NoriError.parse(failures.joined(separator: " · "))
        }
        return HTML.packCalendar(all, now: Date())
    }
}

struct CalendarRow: View {
    @Environment(LibraryStore.self) private var library
    let entry: AiringEntry

    private var source: CatalogProvider { entry.provider ?? library.scope.provider ?? library.provider }

    var body: some View {
        HStack(spacing: 12) {
            // Der Kalender liefert bei manchen Einträgen einen Coverpfad mit;
            // wo nicht, holt die Kachel ihn selbst nach.
            PosterTile(
                title: entry.title,
                slug: entry.slug,
                compact: true,
                coverURL: AniworldClient.coverURL(entry.coverPath, provider: source),
                kind: source
            )
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.body.weight(.medium)).lineLimit(2)
                HStack(spacing: 8) {
                    if !entry.season.isEmpty {
                        Text("S\(entry.season) · F\(entry.episode)")
                    }
                    if !entry.languages.isEmpty {
                        Text(entry.languages.joined(separator: " · "))
                    }
                }
                .font(.caption)
                .foregroundStyle(NoriTheme.muted)
            }
        }
        .padding(.vertical, 4)
    }
}