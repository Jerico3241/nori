import SwiftUI

@main
struct NoriApp: App {
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @State private var catalog: [CatalogItem] = []
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(catalog: catalog, loading: loading, error: error, reload: load)
            }
            .tabItem { Label("Start", systemImage: "house") }

            NavigationStack {
                CatalogView(catalog: catalog, loading: loading, error: error, reload: load)
            }
            .tabItem { Label("Katalog", systemImage: "square.grid.2x2") }

            NavigationStack {
                CalendarView()
            }
            .tabItem { Label("Kalender", systemImage: "calendar") }

            NavigationStack {
                WatchlistView(catalog: catalog)
            }
            .tabItem { Label("Merkliste", systemImage: "heart") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Mehr", systemImage: "gearshape") }
        }
        .tint(NoriTheme.accent)
        .task(id: library.provider) { await load() }
    }

    func load() async {
        loading = catalog.isEmpty
        error = nil
        do {
            let result = try await AniworldClient.shared.getCatalog(provider: library.provider)
            catalog = result.items
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}