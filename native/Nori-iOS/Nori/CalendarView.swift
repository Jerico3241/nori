import SwiftUI

struct CalendarView: View {
    @Environment(LibraryStore.self) private var library
    @State private var payload: CalendarPayload?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        NoriScreen {
            Group {
                if loading && payload == nil {
                    ProgressView("Kalender wird geladen").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error, payload == nil {
                    ContentUnavailableView("Kalender nicht geladen", systemImage: "calendar.badge.exclamationmark", description: Text(error))
                } else if let payload {
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
            }
        }
        .navigationTitle("Kalender")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KindSwitch(provider: Bindable(library).provider)
            }
        }
        .task(id: library.provider) { await load() }
        .refreshable { await load(force: true) }
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