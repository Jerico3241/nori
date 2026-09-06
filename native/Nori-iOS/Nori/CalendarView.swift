import SwiftUI

struct CalendarView: View {
    @Environment(LibraryStore.self) private var library
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
                    if layout == .grid {
                        grid(payload)
                    } else {
                        list(payload)
                    }
                }
            }
        }
        .navigationTitle("Kalender")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KindSwitch(provider: Bindable(library).provider)
            }
            ToolbarItem(placement: .topBarTrailing) {
                LayoutSwitch(layout: $layout)
            }
        }
        .task(id: library.provider) { await load() }
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
            payload = try await AniworldClient.shared.getCalendar(provider: library.provider, force: force)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct CalendarRow: View {
    @Environment(LibraryStore.self) private var library
    let entry: AiringEntry

    private var source: CatalogProvider { entry.provider ?? library.provider }

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