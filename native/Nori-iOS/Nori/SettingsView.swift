import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
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
                Section("Dieses Gerät") {
                    LabeledContent("Version", value: "1.8.0")
                        .listRowBackground(NoriTheme.surface)
                    Text("Läuft nativ auf dem iPhone. Kein Browser, kein Server. Merkliste und Fortschritt liegen nur hier.")
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
                        Text("Filemoon").tag("Filemoon")
                        Text("Doodstream").tag("Doodstream")
                    }
                }
                Section("Wiedergabe") {
                    Toggle("Weiterschauen an der letzten Stelle", isOn: $library.resumeEnabled)
                    Toggle("Nächste Folge automatisch", isOn: $library.autoplayNext)
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
                    Text("Nur auf diesem iPhone. Es gibt keine Cloud und keinen Server.")
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