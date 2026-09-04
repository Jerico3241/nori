import SwiftUI

struct CalendarView: View {
    @Environment(LibraryStore.self) private var library
    @State private var payload: CalendarPayload?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        Group {
            if loading && payload == nil {
                ProgressView("Kalender wird geladen")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, payload == nil {
                ContentUnavailableView(
                    "Kalender nicht geladen",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text(error)
                )
            } else if let payload {
                List {
                    ForEach(grouped(payload.upcoming), id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.rows) { row in
                                NoriSeriesLink(slug: row.slug, titleHint: row.title) {
                                    CalendarRow(entry: row)
                                }
                                .help(row.title)
                            }
                        }
                    }
                    if !payload.recent.isEmpty {
                        Section("Zuletzt") {
                            ForEach(payload.recent) { row in
                                NoriSeriesLink(slug: row.slug, titleHint: row.title) {
                                    CalendarRow(entry: row)
                                }
                                .help(row.title)
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .navigationTitle("Kalender")
        .navigationSubtitle(library.provider.label)
        .toolbar {
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
        .task(id: library.provider) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .noriRefreshRequested)) { _ in
            Task { await load(force: true) }
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
            payload = try await AniworldClient.shared.getCalendar(provider: library.provider, force: force)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct CalendarRow: View {
    let entry: AiringEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PosterTile(title: entry.title, slug: entry.slug, compact: true)
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
