import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var library

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.9.1"
    }

    var body: some View {
        @Bindable var library = library
        NoriScreen {
            List {
                Section("Quelle") {
                    NavigationLink {
                        QuelleSettingsView()
                    } label: {
                        LabeledContent("Vorgabequelle", value: library.provider.label)
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
                    if let provider = library.syncProvider {
                        Button("Jetzt mit \(provider.name) abgleichen") { library.syncNow() }
                            .listRowBackground(NoriTheme.surface)
                        if let stamp = library.syncLastRun {
                            LabeledContent("Letzter Abgleich", value: Date(timeIntervalSince1970: stamp / 1000).formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .listRowBackground(NoriTheme.surface)
                        }
                    } else {
                        LabeledContent("Zustand", value: "nicht eingerichtet")
                            .listRowBackground(NoriTheme.surface)
                        Text("""
                             Hier stand ein iCloud-Schalter. Er hat nie etwas getan: \
                             iCloud verlangt eine Berechtigung aus dem kostenpflichtigen \
                             Apple-Developer-Programm, und ohne sie bleibt der Aufruf \
                             wirkungslos — ohne Fehlermeldung. Merkliste, Verlauf und \
                             Fortschritt liegen ausschließlich auf diesem Gerät.
                             """)
                            .font(.footnote)
                            .foregroundStyle(NoriTheme.muted)
                            .listRowBackground(NoriTheme.surface)
                    }
                }
                Section("Dieses Gerät") {
                    LabeledContent("Version", value: appVersion)
                        .listRowBackground(NoriTheme.surface)
                    Text("Nori läuft nativ und vollständig lokal.")
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
                    Text("Wohin ein Titel führt, der keine eigene Quelle mitbringt — etwa ein Eintrag aus einem älteren gespeicherten Stand. Was in den Listen steht, entscheidet dagegen der Bereich oben rechts: Alle, Anime, Serien oder K-Drama.")
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
    @State private var keyDraft = ""
    @State private var keyStored = TMDBKeyStore.isUserProvided
    @State private var keyNote: String?

    var body: some View {
        NoriScreen {
            Form {
                Section {
                    if keyStored {
                        LabeledContent("Schlüssel", value: "hinterlegt")
                        Button("Schlüssel entfernen", role: .destructive) {
                            TMDBKeyStore.clear()
                            keyStored = false
                            keyDraft = ""
                            keyNote = "Entfernt. Nori zeigt jetzt die Cover der Quellen."
                        }
                    } else {
                        SecureField("TMDB-Schlüssel", text: $keyDraft)
                        Button("Sichern") {
                            if TMDBKeyStore.save(keyDraft) {
                                keyStored = TMDBKeyStore.isUserProvided
                                keyDraft = ""
                                keyNote = "Gesichert. Neue Cover werden ab sofort bei TMDB gesucht."
                            } else {
                                keyNote = "Der Schlüsselbund hat die Ablage abgelehnt."
                            }
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let keyNote {
                        Text(keyNote)
                            .font(.footnote)
                            .foregroundStyle(NoriTheme.muted)
                    }
                } header: {
                    Text("Cover von TMDB")
                } footer: {
                    Text("Ohne Schlüssel nutzt Nori die Cover von AniWorld und Serienstream. Ein eigener Schlüssel (kostenlos bei themoviedb.org) liefert zusätzlich Breitbilder, Kurzbeschreibungen und Bewertungen. Er liegt im Schlüsselbund, nicht im Programm.")
                }

                Section {
                    Button("Verlauf löschen", role: .destructive) { confirm = "history" }
                    Button("Fortschritt löschen", role: .destructive) { confirm = "progress" }
                } footer: {
                    Text("Die Daten werden nur auf diesem Gerät gelöscht.")
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
