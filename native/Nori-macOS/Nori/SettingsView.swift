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
        .frame(width: 540, height: 500)
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
    static let version = "1.14.1"

    static let highlights = [
        "Neuer Bereich „K-Drama“: die koreanischen Serien aus dem Serienstream-Katalog, in Seitenleiste, Katalog und Kalender.",
        "Der laufende Player behält seine Quelle, auch wenn im Hauptfenster ein Titel der anderen Quelle geöffnet wird.",
        "AniWorld ist wieder abspielbar — die Weiterleitung ging bisher an die falsche Domain.",
        "Streams starten zuverlässiger: Der Player schickt jetzt Referer und User-Agent mit.",
        "Cover werden richtig zugeordnet und dauerhaft gespeichert; fehlt ein TMDB-Treffer, greift das Cover der Quelle.",
        "Cover lassen sich in der Detailansicht von Hand auswählen.",
        "Neue Entdecken-Startseite mit Kopfkarussell, „Schau weiter“ und Genre-Zeilen.",
        "Neuer Bereich „Kategorien“ und „Ähnliche Titel“ auf der Detailseite.",
        "Wiedergabe läuft in einem eigenen Fenster mit Vollbild und ⌘W.",
        "TMDB-Schlüssel liegt jetzt im Schlüsselbund statt im Programm — einzutragen unter Einstellungen › Daten.",
        "Detailseite: der Kopfbereich schneidet den Abspielknopf nicht mehr ab.",
        "Das Banner zeigt jetzt Empfehlungen statt angefangener Folgen — die stehen darunter in „Schau weiter“.",
        "Kacheln ohne TMDB-Treffer zeigen jetzt das Cover der Quelle statt eines Buchstabens.",
        "Anime und Serien stehen in einer gemeinsamen Bibliothek; der Umschalter unten links ist jetzt ein Filter.",
        "Leere Kacheln: Die Adresse eines Covers trägt einen Zufallsanteil und ließ sich nicht erraten. Nori liest sie jetzt bei Bedarf aus der Detailseite und merkt sie sich dauerhaft.",
        "Die Folgenliste zeigt Standbild und Beschreibung aus TMDB. Fehlt der deutsche Text, wird die englische Fassung nachgeholt; der Tooltip trägt die vollständige Beschreibung.",
        "Kalender und Merkliste lassen sich als Raster anzeigen, nicht nur als Liste — umgeschaltet wird in der Fensterleiste, wie im Katalog schon länger.",
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
        Form {
            Section {
                if let provider = library.syncProvider {
                    HStack {
                        Button("Jetzt mit \(provider.name) abgleichen") { library.syncNow() }
                        Spacer()
                        if let stamp = library.syncLastRun {
                            Text(Date(timeIntervalSince1970: stamp / 1000).formatted(date: .abbreviated, time: .shortened))
                                .font(.footnote)
                                .foregroundStyle(NoriTheme.muted)
                        }
                    }
                } else {
                    LabeledContent("Zustand", value: "nicht eingerichtet")
                }
            } header: {
                Text("Synchronisation")
            } footer: {
                Text("""
                     Hier stand ein iCloud-Schalter. Er hat nie etwas getan: iCloud \
                     verlangt eine Berechtigung aus dem kostenpflichtigen \
                     Apple-Developer-Programm, und ohne sie bleibt der Aufruf \
                     wirkungslos — ohne Fehlermeldung. Merkliste, Verlauf und \
                     Fortschritt liegen ausschließlich auf diesem Mac.
                     """)
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CoverDiagnosticsRow: View {
    @State private var lines: [String] = []
    @State private var running = false

    private let samples: [(CatalogProvider, String)] = [
        (.serienstream, "black-mirror"),
        (.aniworld, "black-clover"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(running ? "Prüfe…" : "Cover-Abruf prüfen") {
                Task { await run() }
            }
            .disabled(running)

            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func run() async {
        running = true
        lines = []
        defer { running = false }

        // Zuerst der häufigste Grund für leere Kacheln: ohne Schlüssel fragt
        // Nori TMDB gar nicht erst an, und dann bleibt nur das Cover der
        // Quelle — das wiederum eine geladene Detailseite voraussetzt.
        lines.append(
            CoverIndex.shared.hasKey
                ? "TMDB-Schlüssel: hinterlegt"
                : "TMDB-Schlüssel: FEHLT — ohne ihn kommen Cover nur von der Quelle"
        )

        for (provider, slug) in samples {
            lines.append("── \(provider.label) · \(slug)")

            // 1. Detailseite
            let detail: SeriesDetail
            do {
                detail = try await AniworldClient.shared.getSeries(provider: provider, slug: slug)
            } catch {
                lines.append("   Detailseite: \(error.localizedDescription)")
                continue
            }
            lines.append("   Detailseite: gelesen, Titel „\(detail.title)\"")

            // 2. Adresse darin
            guard let path = detail.coverPath, let url = AniworldClient.coverURL(path, provider: provider) else {
                lines.append("   Coveradresse: keine auf der Seite gefunden")
                continue
            }
            lines.append("   Coveradresse: \(url.absoluteString)")

            // 3. Bild
            let verdict = await CoverImageLoader.shared.probe(url, referer: provider.origin + "/")
            lines.append("   Bildabruf: \(verdict)")
        }
    }
}

private struct PrivacySettingsTab: View {
    @Environment(LibraryStore.self) private var library
    @State private var confirm: String?
    @State private var keyDraft = ""
    @State private var keyStored = TMDBKeyStore.isUserProvided
    @State private var keyNote: String?

    var body: some View {
        Form {
            Section {
                if keyStored {
                    LabeledContent("TMDB-Schlüssel") {
                        HStack(spacing: 10) {
                            Text("hinterlegt")
                                .foregroundStyle(NoriTheme.muted)
                            Button("Entfernen", role: .destructive) {
                                TMDBKeyStore.clear()
                                keyStored = false
                                keyDraft = ""
                                keyNote = "Entfernt. Nori zeigt jetzt die Cover der Quellen."
                            }
                        }
                    }
                } else {
                    LabeledContent("TMDB-Schlüssel") {
                        HStack(spacing: 10) {
                            SecureField("noch keiner", text: $keyDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
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
                    }
                }
                if let keyNote {
                    Text(keyNote)
                        .font(.footnote)
                        .foregroundStyle(NoriTheme.muted)
                }
            } header: {
                Text("Cover von TMDB")
            } footer: {
                Text("""
                     Ohne Schlüssel nutzt Nori die Cover von AniWorld und Serienstream. \
                     Ein eigener Schlüssel (kostenlos bei themoviedb.org) liefert zusätzlich \
                     Breitbilder, Kurzbeschreibungen und Bewertungen. Er liegt im \
                     Schlüsselbund, nicht im Programm.
                     """)
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
            }

            Section {
                CoverDiagnosticsRow()
            } header: {
                Text("Cover-Diagnose")
            } footer: {
                Text("""
                     Prüft den Weg, auf dem ein Cover entsteht: Detailseite laden, \
                     Adresse darin finden, Bild abrufen. Bleiben Kacheln leer, zeigt \
                     der Befund, an welchem der drei Schritte es scheitert.
                     """)
                    .font(.footnote)
                    .foregroundStyle(NoriTheme.muted)
            }

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
                Text("Die Daten werden nur auf diesem Mac gelöscht.")
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

