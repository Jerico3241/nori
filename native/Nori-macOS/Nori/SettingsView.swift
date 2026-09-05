import SwiftUI

/// Einstellungen liegen auf dem Mac im Einstellungsfenster (⌘,) und nicht in
/// einem Tab der Hauptnavigation.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            PlaybackSettingsTab()
                .tabItem { Label("Wiedergabe", systemImage: "play.rectangle") }
            SyncSettingsTab()
                .tabItem { Label("Synchronisation", systemImage: "icloud") }
            PrivacySettingsTab()
                .tabItem { Label("Daten", systemImage: "lock") }
            WhatsNewSettingsTab()
                .tabItem { Label("Neuerungen", systemImage: "sparkles") }
        }
        // Höhe am längsten Bereich ausgerichtet. Mit 340 pt wurde der
        // Allgemein-Bereich beschnitten, sobald die Neuerungen dazukamen.
        .frame(width: 540, height: 430)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(LibraryStore.self) private var library

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? NoriRelease.version
    }

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Picker("Aktive Quelle", selection: $library.provider) {
                    ForEach(CatalogProvider.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
            } footer: {
                Text("AniWorld zeigt Anime, Serienstream zeigt Serien. Katalog, Kalender und Player folgen der Auswahl.")
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
            }

            Section {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Bibliotheksschema", value: "v\(LibraryStore.schemaVersion)")
            }

        }
        .formStyle(.grouped)
    }
}

private struct WhatsNewSettingsTab: View {
    var body: some View {
        Form {
            // Titel als Header-Closure: einen Initialisierer mit Titel *und*
            // Footer gibt es nicht.
            Section {
                ForEach(NoriRelease.highlights, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(NoriTheme.accent)
                        Text(line)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text("Neu in \(NoriRelease.version)")
            } footer: {
                Text("Vollständige Liste aller Änderungen: CHANGELOG.md im Projektverzeichnis.")
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
            }
        }
        .formStyle(.grouped)
    }
}

/// Kurzfassung des Changelogs für das Einstellungsfenster. Die App wird als
/// ZIP verteilt, es gibt also keine Release-Seite, auf der so etwas stünde.
/// Vollständig in CHANGELOG.md im Projektverzeichnis.
enum NoriRelease {
    static let version = "1.10.0"

    static let highlights = [
        "AniWorld ist wieder abspielbar — die Weiterleitung ging bisher an die falsche Domain.",
        "Streams starten zuverlässiger: Der Player schickt jetzt Referer und User-Agent mit.",
        "Cover werden richtig zugeordnet und dauerhaft gespeichert; fehlt ein TMDB-Treffer, greift das Cover der Quelle.",
        "Cover lassen sich in der Detailansicht von Hand auswählen.",
        "Neue Entdecken-Startseite mit Kopfkarussell, „Schau weiter“ und Genre-Zeilen.",
        "Neuer Bereich „Kategorien“ und „Ähnliche Titel“ auf der Detailseite.",
        "Wiedergabe läuft in einem eigenen Fenster mit Vollbild und ⌘W.",
    ]
}

private struct PlaybackSettingsTab: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            Section("Sprache") {
                Picker("Bevorzugte Sprache", selection: $library.langPref) {
                    Text("GerDub").tag("DE")
                    Text("GerSub").tag("GerSub")
                    Text("EN").tag("EN")
                }
                .pickerStyle(.segmented)
            }

            Section("Hoster") {
                Picker("Bevorzugter Hoster", selection: $library.hosterPref) {
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
                Toggle("Nächste Folge automatisch starten", isOn: $library.autoplayNext)
                Picker("Geschwindigkeit", selection: $library.playbackSpeed) {
                    Text("0,75×").tag(Float(0.75))
                    Text("1×").tag(Float(1.0))
                    Text("1,25×").tag(Float(1.25))
                    Text("1,5×").tag(Float(1.5))
                    Text("2×").tag(Float(2.0))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SyncSettingsTab: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        Form {
            Section {
                Toggle("Mit iCloud synchronisieren", isOn: $library.cloudSyncEnabled)
                if library.cloudSyncEnabled {
                    HStack {
                        Button("Jetzt synchronisieren") { library.syncNow() }
                        Spacer()
                        if let stamp = library.cloudLastSync {
                            Text(Date(timeIntervalSince1970: stamp / 1000).formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(NoriTheme.muted)
                        }
                    }
                }
            } footer: {
                Text("Synchronisiert Merkliste, Verlauf, Wiedergabefortschritt und Einstellungen zwischen Apple-Geräten mit derselben Apple-ID. Ohne aktivierte Synchronisation bleiben alle Daten auf diesem Mac.")
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettingsTab: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirm: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Verlauf") {
                    HStack(spacing: 10) {
                        Text("\(library.recents.count) Einträge")
                            .foregroundStyle(NoriTheme.muted)
                        Button("Löschen…", role: .destructive) { confirm = "history" }
                    }
                }
                LabeledContent("Wiedergabefortschritt") {
                    HStack(spacing: 10) {
                        Text("\(library.progress.count) Folgen")
                            .foregroundStyle(NoriTheme.muted)
                        Button("Löschen…", role: .destructive) { confirm = "progress" }
                    }
                }
            } footer: {
                Text(library.cloudSyncEnabled
                     ? "Bei aktivierter Synchronisation wird der gelöschte Stand auch mit iCloud abgeglichen."
                     : "Die Daten werden nur auf diesem Mac gelöscht.")
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            confirm == "progress" ? "Wiedergabefortschritt wirklich löschen?" : "Verlauf wirklich löschen?",
            isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })
        ) {
            Button("Löschen", role: .destructive) {
                if confirm == "progress" { library.clearProgress() } else { library.clearHistory() }
                confirm = nil
            }
            Button("Abbrechen", role: .cancel) { confirm = nil }
        } message: {
            Text("Das lässt sich nicht rückgängig machen.")
        }
    }
}
