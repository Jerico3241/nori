import SwiftUI

// Die Abschnitte der Startseite.
//
// Jeder Abschnitt stellt nur dar, was `HomeFeedService` ihm gibt, und
// entscheidet selbst genau eine Sache: ob er überhaupt erscheint. Eine
// Überschrift ohne Inhalt ist ein Versprechen, das die Seite nicht hält —
// „Weiterschauen" über einer leeren Reihe ist schlechter als gar kein
// „Weiterschauen".

// MARK: - Weiterschauen

/// „Weiterschauen" — ausschließlich aus dem persönlichen Fortschritt.
///
/// Nicht aus TMDB, nicht aus Beliebtheit: hier stehen die Folgen, die
/// angefangen und nicht zu Ende gesehen wurden, die zuletzt angesehene zuerst.
/// Die Auswahl trifft `LibraryStore.continueWatching()` — dieselbe Funktion
/// wie bisher, denn sie war nie das Problem.
///
/// Ein Tipp startet unmittelbar die Wiedergabe an der gespeicherten Stelle.
/// Das ist die einzige Kachel der Startseite, die das tut; alle anderen führen
/// zur Detailseite.
struct ContinueWatchingSection: View {
    let items: [WatchProgress]
    let width: CGFloat
    /// Welcher Eintrag gerade geholt wird — die Kachel zeigt so lange einen
    /// Schleier. Ohne das wirkt das Antippen tot: bis feststeht, welche Folge
    /// läuft, muss erst die Detailseite da sein.
    let preparing: String?
    let onPlay: (WatchProgress) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HomeSectionHeader("Weiterschauen")
                HomeRail {
                    ForEach(items) { item in
                        card(item)
                    }
                }
            }
        }
    }

    private func card(_ item: WatchProgress) -> some View {
        Button {
            onPlay(item)
        } label: {
            HomeLandscapeCard(item: item, width: width)
                .overlay(alignment: .top) { veil(for: item) }
        }
        .buttonStyle(NoriPressStyle(scale: 0.97))
        .accessibilityLabel("\(item.title), Staffel \(item.season) Folge \(item.episode), fortsetzen")
    }

    @ViewBuilder
    private func veil(for item: WatchProgress) -> some View {
        if preparing == item.id {
            ZStack {
                Color.black.opacity(0.45)
                ProgressView().tint(.white)
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.landscapeRadius, style: .continuous))
            .transition(.opacity)
        }
    }
}

// MARK: - Posterreihe

/// Die Grundform der übrigen Reihen: Überschrift und Posterkacheln.
///
/// „Neu & beliebt", „Für dich", „Gerade im Trend", „Top bewertet" und die
/// Genre-Reihen sehen gleich aus — sie unterscheiden sich in dem, was drin
/// steht, und das ist an dieser Stelle bereits entschieden.
struct HomePosterSection: View {
    let title: String
    let items: [HomeCandidate]
    let width: CGFloat
    /// Abzeichen zeigen? Nur in „Neu & beliebt" — ein „NEU" in jeder Reihe
    /// wäre keine Auszeichnung mehr.
    var showsBadges: Bool = false
    var now: Date = Date()

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HomeSectionHeader(title)
                HomeRail {
                    ForEach(items) { item in
                        link(item)
                    }
                }
            }
        }
    }

    private func link(_ item: HomeCandidate) -> some View {
        NoriSeriesLink(
            slug: item.title.slug,
            titleHint: item.title.title,
            scaleOnPress: true,
            provider: item.title.provider
        ) {
            HomePosterCard(
                candidate: item,
                width: width,
                badge: showsBadges ? HomeBadge.of(item, now: now) : nil
            )
        }
    }
}

// MARK: - Neue Episoden

/// „Neue Episoden" — was seit gestern dazugekommen ist.
///
/// Quelle ist Noris eigener Kalender, nicht TMDB: TMDB weiß nicht, was
/// AniWorld heute hochgeladen hat. Sortiert wird chronologisch, die neueste
/// zuerst — ausdrücklich **nicht** nach Beliebtheit. Beliebtheit beantwortet
/// eine andere Frage, und die steht eine Reihe weiter oben.
///
/// Als Liste und nicht als Kachelreihe, weil hier die Angaben zählen: Staffel,
/// Folge, Sprache, wann. In einer Kachel stünde davon die Hälfte unter dem
/// Bild und die andere gar nicht.
struct NewEpisodesSection: View {
    let entries: [AiringEntry]
    let preparing: String?
    let onPlay: (AiringEntry) -> Void
    let onCalendar: () -> Void

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HomeSectionHeader("Neue Episoden") {
                    Button("Kalender", action: onCalendar)
                        .buttonStyle(.plain)
                        .foregroundStyle(NoriTheme.muted)
                }
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        row(entry)
                        if entry.id != entries.last?.id {
                            Divider().overlay(NoriTheme.border)
                        }
                    }
                }
                .padding(.horizontal, HomeMetrics.screen)
                // Auf dem iPad nicht über die ganze Breite ziehen: eine Zeile
                // aus 118 Punkten Bild und zwei Zeilen Text über 1300 Punkte
                // hat in der Mitte nichts als Leere, und der Fortschrittsring
                // steht einen halben Meter vom Titel entfernt. Dieselbe Spalte
                // wie die Folgenliste der Detailseite — die Seiten sollen sich
                // nicht nur ähnlich sehen, sondern gleich gebaut sein.
                .frame(maxWidth: SeriesMetrics.content, alignment: .leading)
            }
        }
    }

    private func row(_ entry: AiringEntry) -> some View {
        Button {
            onPlay(entry)
        } label: {
            HomeEpisodeCard(entry: entry)
                .overlay(alignment: .leading) { veil(for: entry) }
        }
        .buttonStyle(NoriPressStyle(scale: 0.99))
    }

    @ViewBuilder
    private func veil(for entry: AiringEntry) -> some View {
        if preparing == entry.id {
            ZStack {
                Color.black.opacity(0.5)
                ProgressView().tint(.white)
            }
            .frame(width: HomeMetrics.episodeThumb, height: HomeMetrics.episodeThumb * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.thumbRadius, style: .continuous))
        }
    }
}

// MARK: - Zustände

/// Die Meldung, wenn beide Kataloge nicht geladen werden konnten.
///
/// Getrennt vom Fehler der Wiedergabe: der eine betrifft die ganze Seite, der
/// andere eine einzelne Kachel.
struct HomeErrorBanner: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(text, systemImage: "wifi.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.red)
            Button("Erneut laden", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: HomeMetrics.landscapeRadius, style: .continuous)
                .fill(NoriTheme.surface)
        }
        .padding(.horizontal, HomeMetrics.screen)
    }
}

/// Der erste Aufbau, solange noch kein Titel dasteht.
///
/// Ein Umriss der späteren Seite statt eines kreisenden Rädchens: so springt
/// das Layout nicht, wenn die Daten eintreffen, und es ist von Anfang an
/// erkennbar, was dort erscheinen wird.
struct HomeSkeleton: View {
    let heroHeight: CGFloat
    let posterWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: HomeMetrics.section) {
            RoundedRectangle(cornerRadius: 0)
                .fill(NoriTheme.elevated)
                .frame(height: heroHeight)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, NoriTheme.bg], startPoint: .center, endPoint: .bottom)
                }

            ForEach(0 ..< 2, id: \.self) { row in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(NoriTheme.elevated)
                        .frame(width: 170, height: 20)
                        .padding(.horizontal, HomeMetrics.screen)
                    HStack(spacing: HomeMetrics.rail) {
                        ForEach(0 ..< 4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: HomeMetrics.posterRadius, style: .continuous)
                                .fill(NoriTheme.elevated)
                                .frame(width: posterWidth, height: posterWidth * 1.5)
                        }
                    }
                    .padding(.horizontal, HomeMetrics.screen)
                }
                .id(row)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Startseite wird geladen")
    }
}
