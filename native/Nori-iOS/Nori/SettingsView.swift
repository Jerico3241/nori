import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.9.0"
    }

    var body: some View {
        @Bindable var library = library
        NoriScreen {
            List {
                Section("Quelle") {
                    NavigationLink {
                        QuelleSettingsView()
                    } label: {
                        LabeledContent("Aktive Quelle", value: library.provider.label)
                    }
                    .listRowBackground(NoriTheme.surface)
                }
                Section("Wiedergabe") {
                    NavigationLink("Sprache, Hoster, Resume") {
                        PlaybackSettingsView()
                    }
                    .listRowBackground(NoriTheme.surface)
                }
                Section("Synchronisation") {
                    Toggle("Mit iCloud synchronisieren", isOn: $library.cloudSyncEnabled)
                        .listRowBackground(NoriTheme.surface)
                    if library.cloudSyncEnabled {
                        Button("Jetzt synchronisieren") { library.syncNow() }
                            .listRowBackground(NoriTheme.surface)
                        if let stamp = library.cloudLastSync {
                            LabeledContent("Letzter Stand", value: Date(timeIntervalSince1970: stamp / 1000).formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .listRowBackground(NoriTheme.surface)
                        }
                    }
                    Text("Synchronisiert Merkliste, Verlauf, Wiedergabefortschritt und Einstellungen zwischen deinen Apple-Geräten mit derselben Apple-ID.")
                        .font(.footnote)
                        .foregroundStyle(NoriTheme.muted)
                        .listRowBackground(NoriTheme.surface)
                }
                Section("Dieses Gerät") {
                    LabeledContent("Version", value: appVersion)
                        .listRowBackground(NoriTheme.surface)
                    Text("Nori läuft nativ. Ohne aktivierte iCloud-Synchronisation bleiben Merkliste und Fortschritt ausschließlich auf diesem Gerät.")
                        .font(.footnote)
                        .foregroundStyle(NoriTheme.muted)
                        .listRowBackground(NoriTheme.surface)
                }
                Section("Datenschutz") {
                    NavigationLink("Verlauf und Fortschritt") {
                        PrivacySettingsView()
                    }
                    .listRowBackground(NoriTheme.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Einstellungen")
    }
}

struct QuelleSettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        NoriScreen {
            Form {
                Section {
                    Picker("Quelle", selection: $library.provider) {
                        ForEach(CatalogProvider.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("AniWorld zeigt Anime, Serienstream zeigt Serien. Katalog, Kalender und Player folgen der Auswahl.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Quelle")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaybackSettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        NoriScreen {
            Form {
                Section("Sprache") {
                    Picker("Sprache", selection: $library.langPref) {
                        Text("GerDub").tag("DE")
                        Text("GerSub").tag("GerSub")
                        Text("EN").tag("EN")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Hoster") {
                    Picker("Hoster", selection: $library.hosterPref) {
                        Text("VOE").tag("VOE")
                        Text("Vidmoly").tag("Vidmoly")
                        Text("Vidoza").tag("Vidoza")
                        Text("Lulustream").tag("Lulustream")
                        Text("SpeedFiles").tag("SpeedFiles")
                        Text("Filemoon").tag("Filemoon")
                        Text("Doodstream").tag("Doodstream")
                    }
                }
                Section("Wiedergabe") {
                    Toggle("Weiterschauen an der letzten Stelle", isOn: $library.resumeEnabled)
                    Toggle("Nächste Folge automatisch", isOn: $library.autoplayNext)
                    Picker("Geschwindigkeit", selection: $library.playbackSpeed) {
                        Text("0,75×").tag(Float(0.75))
                        Text("1×").tag(Float(1.0))
                        Text("1,25×").tag(Float(1.25))
                        Text("1,5×").tag(Float(1.5))
                        Text("2×").tag(Float(2.0))
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Wiedergabe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySettingsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirm: String?

    var body: some View {
        NoriScreen {
            Form {
                Section {
                    Button("Verlauf löschen", role: .destructive) { confirm = "history" }
                    Button("Fortschritt löschen", role: .destructive) { confirm = "progress" }
                } footer: {
                    Text(library.cloudSyncEnabled ? "Bei aktivierter Synchronisation wird der gelöschte Stand auch mit iCloud abgeglichen." : "Die Daten werden nur auf diesem Gerät gelöscht.")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Datenschutz")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Wirklich löschen?", isPresented: Binding(
            get: { confirm != nil },
            set: { if !$0 { confirm = nil } }
        )) {
            Button("Löschen", role: .destructive) {
                if confirm == "progress" { library.clearProgress() }
                else { library.clearHistory() }
                confirm = nil
            }
            Button("Abbrechen", role: .cancel) { confirm = nil }
        }
    }
}
