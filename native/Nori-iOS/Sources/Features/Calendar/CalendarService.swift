import SwiftUI

/// Lädt die Veröffentlichungen beider Quellen und hält sie bereit.
///
/// Die Verfügbarkeit entscheiden ausschließlich Noris Provider: AniWorld und
/// Serienstream sagen, welche Folge wann bei ihnen steht. TMDB liefert später
/// Titel und Bilder dazu (siehe `CalendarEpisodeMeta`), darf aber nie darüber
/// bestimmen, ob ein Eintrag überhaupt erscheint — TMDB kennt Ausstrahlungen,
/// nicht Noris Bestand.
///
/// Der Dienst lädt **einmal** und hält das Ergebnis. Modus, Tag und Filter
/// wechseln danach ohne Netz: der Kalender hat keinen Grund, beim Wischen von
/// „Heute" auf „Woche" zwei Seiten neu zu holen.
@MainActor
@Observable
final class CalendarService {
    /// Alle zusammengeführten Veröffentlichungen, chronologisch.
    private(set) var releases: [CalendarRelease] = []
    private(set) var loading = false
    /// Meldung, wenn **beide** Quellen ausgefallen sind. Fällt nur eine aus,
    /// zeigt der Kalender die andere weiter und schweigt.
    private(set) var error: String?
    /// Wann der Stand geholt wurde — für „Aktualisiert vor …".
    private(set) var fetchedAt: Date?

    /// Wonach zuletzt geladen wurde. Ein Bereichswechsel muss neu laden, ein
    /// Moduswechsel nicht.
    private var loadedKey: String?

    /// Die Einträge holen, zusammenführen und ablegen.
    ///
    /// - Parameters:
    ///   - scope: der Bereich der Bibliothek; schränkt auf eine Quelle ein.
    ///   - slugs: zugelassene Serien, wenn der Bereich an einem Genre hängt.
    ///     `nil` heißt „nicht einschränken" — nicht „nichts zeigen": solange
    ///     der Katalog noch lädt, ist ein vollständiger Kalender die bessere
    ///     Antwort als ein leerer.
    ///   - force: am Netz vorbei am Zwischenspeicher vorbei neu holen.
    func load(scope: LibraryScope, slugs: Set<String>?, force: Bool = false) async {
        let key = "\(scope.rawValue)|\(slugs?.count ?? -1)"
        if !force, key == loadedKey, !releases.isEmpty { return }

        loading = releases.isEmpty || force
        if force { error = nil }

        let (entries, failures) = await Self.fetch(scope: scope, slugs: slugs, force: force)

        if entries.isEmpty, !failures.isEmpty {
            // Nur melden, wenn nichts kam. Eine ausgefallene Quelle darf die
            // andere nicht mitreißen.
            error = failures.joined(separator: " · ")
            loading = false
            return
        }

        releases = CalendarMerge.releases(from: entries, calendar: Calendar.current)
        fetchedAt = Date()
        loadedKey = key
        error = nil
        loading = false
    }

    // MARK: - Abruf

    /// Die Einträge beider Quellen holen, samt Fehlschlägen je Quelle.
    ///
    /// Beide Seiten gleichzeitig: hintereinander dauert der Aufbau doppelt so
    /// lange, und die zweite Quelle wartet ohne Grund. Der Zwischenspeicher
    /// liegt in `AniworldClient.getCalendar` — ein erneuter Aufruf innerhalb
    /// von zwanzig Minuten geht nicht ans Netz.
    ///
    /// Fehlschläge werden gesammelt statt geworfen: fällt eine Seite aus, zeigt
    /// der Kalender die andere weiter.
    static func fetch(
        scope: LibraryScope,
        slugs: Set<String>?,
        force: Bool
    ) async -> (entries: [AiringEntry], failures: [String]) {
        let sources = scope.provider.map { [$0] } ?? CatalogProvider.allCases
        var entries: [AiringEntry] = []
        var failures: [String] = []

        await withTaskGroup(of: Result<CalendarPayload, Error>.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        return .success(try await AniworldClient.shared.getCalendar(provider: source, force: force))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await outcome in group {
                switch outcome {
                case .success(let payload):
                    entries.append(contentsOf: payload.upcoming)
                    entries.append(contentsOf: payload.recent)
                case .failure(let failure):
                    failures.append(failure.localizedDescription)
                }
            }
        }

        if let slugs {
            entries.removeAll { !slugs.contains($0.slug) }
        }
        return (entries, failures)
    }

    /// Derselbe Abruf als `CalendarPayload`, aufgeteilt in „kommend" und
    /// „kürzlich".
    ///
    /// Für die Startseite, die aus dem Kalender nur die Reihe „Neue Episoden"
    /// speist und dafür den gelaufenen Teil braucht. Sie bekommt bewusst
    /// dieselbe Funktion wie der Kalender-Tab, damit beide denselben Stand und
    /// denselben Zwischenspeicher benutzen.
    ///
    /// Wirft, wenn **nichts** kam — die Startseite blendet die Reihe dann aus.
    static func payload(
        scope: LibraryScope,
        slugs: Set<String>? = nil,
        force: Bool
    ) async throws -> CalendarPayload {
        let (entries, failures) = await fetch(scope: scope, slugs: slugs, force: force)
        if entries.isEmpty, !failures.isEmpty {
            throw NoriError.parse(failures.joined(separator: " · "))
        }
        return HTML.packCalendar(entries, now: Date())
    }
}
