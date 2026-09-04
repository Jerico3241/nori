import SwiftUI

struct KindSwitch: View {
    @Binding var provider: CatalogProvider
    @State private var drag: CGFloat? = nil
    @State private var armed = false
    @State private var startX: CGFloat = 0

    private let width: CGFloat = 168
    private let height: CGFloat = 36
    private let pad: CGFloat = 2

    private var thumb: CGFloat { (width / 2) - pad }
    private var travelMax: CGFloat { width - thumb - pad * 2 }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(NoriTheme.surface)
            Capsule()
                .fill(NoriTheme.accent)
                .frame(width: thumb, height: height - pad * 2)
                .offset(x: pad + travel)
            HStack(spacing: 0) {
                Text("Anime")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(provider == .aniworld ? NoriTheme.bg : NoriTheme.muted)
                    .frame(maxWidth: .infinity)
                Text("Serien")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(provider == .serienstream ? NoriTheme.bg : NoriTheme.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: width, height: height)
        .overlay {
            Capsule().strokeBorder(NoriTheme.border, lineWidth: 1)
        }
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if !armed {
                        armed = true
                        startX = value.startLocation.x
                    }
                    drag = value.translation.width
                }
                .onEnded { value in
                    let projected = travelBase + value.translation.width
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        provider = projected > travelMax / 2 ? .serienstream : .aniworld
                        drag = nil
                        armed = false
                    }
                }
        )
        .onTapGesture { location in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                provider = location.x < width / 2 ? .aniworld : .serienstream
            }
        }
        .animation(drag == nil ? .spring(response: 0.32, dampingFraction: 0.86) : nil, value: provider)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Anime oder Serien")
        .accessibilityValue(provider == .aniworld ? "Anime" : "Serien")
        .accessibilityAddTraits(.isButton)
    }

    private var travelBase: CGFloat {
        provider == .serienstream ? travelMax : 0
    }

    private var travel: CGFloat {
        min(max(travelBase + (drag ?? 0), 0), travelMax)
    }
}

struct HomeView: View {
    @Environment(LibraryStore.self) private var library
    let catalog: [CatalogItem]
    let loading: Bool
    let error: String?
    let reload: () async -> Void

    var body: some View {
        NoriScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Nori")
                        .font(.largeTitle.weight(.semibold))
                    if let error {
                        Text(error).font(.subheadline).foregroundStyle(.red)
                        Button("Erneut laden") { Task { await reload() } }
                    }
                    let watching = library.continueWatching()
                    if !watching.isEmpty {
                        Text("Weiterschauen")
                            .font(.title3.weight(.semibold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(watching) { item in
                                    NoriSeriesLink(
                                        slug: item.slug,
                                        titleHint: item.title,
                                        scaleOnPress: true,
                                        provider: providerFromPath(item.episodePath)
                                    ) {
                                        ContinueCard(item: item)
                                    }
                                }
                            }
                        }
                    }
                    Text("Beliebte \(library.provider.kind)")
                        .font(.title3.weight(.semibold))
                    if loading && catalog.isEmpty {
                        ProgressView("Nori wird geladen")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 14) {
                            ForEach(catalog.prefix(36)) { item in
                                NoriSeriesLink(slug: item.slug, titleHint: item.title, scaleOnPress: true) {
                                    PosterTile(title: item.title, slug: item.slug)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KindSwitch(provider: Bindable(library).provider)
            }
        }
    }
}

struct ContinueCard: View {
    @Environment(LibraryStore.self) private var library
    let item: WatchProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterTile(title: item.title, slug: item.slug, compact: true)
            Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
            Text("S\(item.season) · F\(item.episode) · \(formatClock(item.positionSec))")
                .font(.caption2)
                .foregroundStyle(NoriTheme.muted)
            ProgressView(value: watchRatio(item))
                .tint(NoriTheme.accent)
        }
        .frame(width: 140)
    }
}
