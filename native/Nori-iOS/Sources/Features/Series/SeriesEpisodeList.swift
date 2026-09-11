import SwiftUI

// Staffelwahl und Folgenliste.
//
// Die Staffel ist ein Auswahlmenü, keine Reihe von Chips und keine
// aufklappbare Liste: gewählt wird eine, und die steht danach vollständig da.
// Es gibt keinen Zwischenschritt zwischen „Staffel 2" und der zweiten Folge
// darin.

struct SeriesEpisodeList: View {
    let detail: SeriesDetail
    let season: String
    let provider: CatalogProvider
    let episodeInfo: [Int: EpisodeInfo]
    /// Das Artwork der Serie — Rückfall für Folgen ohne eigenes Standbild.
    let artwork: SeriesArtwork
    let tone: Color?
    /// Die Staffel wird gerade nachgeladen. Die vorherige Liste bleibt
    /// solange stehen und wird nur abgeblendet; ein Ladekringel an ihrer
    /// Stelle ließe die Seite bei jedem Wechsel zusammenfallen.
    let switching: Bool
    let width: CGFloat
    let select: (String) -> Void
    let play: (Episode, Double) -> Void

    @Environment(LibraryStore.self) private var library
    @AppStorage(NoriGlassSetting.key) private var glass = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            seasonRow

            if detail.episodes.isEmpty {
                empty
            } else {
                let next = library.nextPlay(
                    slug: detail.slug, season: season, episodes: detail.episodes, source: provider
                ).episode

                LazyVStack(spacing: SeriesMetrics.gap) {
                    ForEach(detail.episodes) { episode in
                        SeriesEpisodeCard(
                            detail: detail,
                            episode: episode,
                            season: season,
                            provider: provider,
                            info: episodeInfo[episode.number],
                            artwork: artwork,
                            tone: tone,
                            highlighted: episode.number == next,
                            width: width,
                            play: play
                        )
                    }
                }
                .opacity(switching ? 0.42 : 1)
                .noriAnimation(NoriMotion.micro, value: switching)
            }
        }
        .padding(.horizontal, NoriSpacing.screen)
    }

    /// Staffelwähler links, Anzahl rechts.
    private var seasonRow: some View {
        HStack(alignment: .center) {
            seasonMenu
            Spacer(minLength: 12)
            Text(countLabel)
                .font(.footnote)
                .foregroundStyle(NoriTheme.muted)
        }
    }

    @ViewBuilder
    private var seasonMenu: some View {
        let binding = Binding(get: { season }, set: { select($0) })

        Menu {
            Picker("Staffel", selection: binding) {
                ForEach(detail.seasons) { ref in
                    Text(ref.label).tag(ref.id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                Text(seasonLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(NoriTheme.muted)
            }
            .foregroundStyle(NoriTheme.fg)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .frame(minWidth: 136, alignment: .leading)
            .noriGlass(Capsule(), enabled: glass, off: NoriTheme.elevated.opacity(0.92))
            .overlay { Capsule().strokeBorder(.white.opacity(glass ? 0 : 0.14)) }
        }
        .disabled(detail.seasons.count < 2)
        .accessibilityLabel("Staffel wählen, aktuell \(seasonLabel)")
    }

    private var seasonLabel: String {
        detail.seasons.first(where: { $0.id == season })?.label ?? "Staffel \(season)"
    }

    /// „12 Folgen". Bei einem Abschnitt aus Filmen heißen sie auch so.
    private var countLabel: String {
        let count = detail.episodes.count
        if season == "filme" { return count == 1 ? "1 Film" : "\(count) Filme" }
        return count == 1 ? "1 Folge" : "\(count) Folgen"
    }

    private var empty: some View {
        Text("Für diese Staffel liegen keine Folgen vor.")
            .font(.subheadline)
            .foregroundStyle(NoriTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }
}
