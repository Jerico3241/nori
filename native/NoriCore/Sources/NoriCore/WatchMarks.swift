import Foundation

// Der Sehstand: herleiten und von Hand setzen.
//
// Die Entsprechung zu `shared/nori-core/src/watch.ts`. Beide Kerne rechnen
// hier dasselbe, weil beide denselben Stand aus Google Drive lesen: würde der
// Fernseher „gesehen" anders herleiten als das iPhone, zeigten zwei Geräte auf
// identischen Daten zwei verschiedene Bibliotheken.
//
// Beides steht in **einer** Datei, weil beides dieselbe Grenze benutzt: was
// „angefasst" heißt (Position > 0 oder abgeschlossen) entscheidet, was
// `watchSummary` zählt und was „als ungesehen markieren" schreiben muss.
// Getrennt hätten sie beim nächsten Eingriff auseinanderlaufen können. Die
// Mac-App baut `WatchlistModel.swift` nicht — sie hat eine eigene, schlankere
// Merkliste —, den Sehstand braucht sie trotzdem.
//
// ## Warum „ungesehen" kein Löschen ist
//
// Ein Eintrag, der lokal verschwindet, kommt beim nächsten Abgleich vom
// nächsten Gerät zurück — die Zusammenführung kennt für Fortschritt keinen
// Grabstein je Eintrag, nur den globalen `progressClearedAt`. „Als ungesehen
// markieren" schreibt deshalb einen **neuen, leeren** Stand mit frischem
// Zeitstempel: Position 0, nicht abgeschlossen. Der gewinnt die
// Zusammenführung regulär, und `watchSummary` zählt ihn wie „nie angefasst",
// weil dort nur zählt, was Position > 0 oder `completed` trägt.
//
// ## Warum Millisekunden
//
// `WatchProgress.updatedAt` ist überall in Nori „Millisekunden seit 1970" —
// der Player schreibt so, die Zusammenführung vergleicht so, `library.json`
// steht so auf der Platte. Genau das ging vorher schief: „Staffel als gesehen
// markieren" lag in der iOS-Ansicht und stempelte mit
// `Date().timeIntervalSince1970`, also in **Sekunden**. Ein solcher Eintrag ist
// gegen jeden echten Zeitstempel tausendfach zu alt: der Verlauf sortierte ihn
// ans Ende, und beim nächsten Abgleich hat ihn die Fassung eines anderen
// Geräts stillschweigend wieder überschrieben. Hier gibt es nur noch eine
// Stelle, an der die Marke entsteht.

// MARK: - Status

/// Der persönliche Stand zu einem gemerkten Titel.
///
/// Drei Fälle, und die Grenze zwischen dem ersten und dem zweiten ist die,
/// die man leicht falsch zieht: „ungesehen" heißt **nicht** „noch nicht
/// fertig". Ein Titel, in dem 40 von 50 Folgen laufen, ist angefangen, nicht
/// ungesehen.
enum WatchState: String, Codable, CaseIterable, Hashable {
    /// Gemerkt, aber noch nie etwas davon abgespielt.
    case unseen
    /// Es läuft etwas, es ist aber noch nicht durch.
    case started
    /// Alles, was Nori zu dem Titel kennt, ist abgeschlossen.
    case seen

    var label: String {
        switch self {
        case .unseen: return "Ungesehen"
        case .started: return "Angefangen"
        case .seen: return "Gesehen"
        }
    }
}

/// Was aus dem Fortschritt eines Titels herausgelesen werden kann.
///
/// ## Wofür „ratio" steht
///
/// Der Stand **in der zuletzt gesehenen Folge**, nicht der Anteil der
/// gesehenen Folgen an der Serie. Das ist eine bewusste Einschränkung: wie
/// viele Folgen eine Serie insgesamt hat, steht nur auf der Detailseite der
/// Quelle, und die müsste für jede Kachel der Merkliste einzeln geholt
/// werden. Ein Balken, der „74 % der Serie" behauptet und dabei durch die
/// Zahl der *bisher geöffneten* Folgen teilt, wäre schlicht falsch — er
/// stünde bei der ersten Folge einer Serie mit fünfzig auf 100 %.
///
/// Die Oberfläche schreibt deshalb „S1 · F7 · 58 %" daneben: Staffel, Folge,
/// und wie weit in dieser Folge. Damit sagt der Balken genau das, was er
/// misst.
struct WatchSummary: Hashable {
    var state: WatchState
    /// Stand in der laufenden Folge, 0…1. Bei `seen` immer 1, bei `unseen`
    /// immer 0.
    var ratio: Double
    /// Die Staffel, in der zuletzt etwas lief.
    var season: String?
    /// Die Folge, in der zuletzt etwas lief.
    var episode: Int?
    /// Wie viele Folgen dieses Titels abgeschlossen sind.
    var completedEpisodes: Int
    /// Wann zuletzt etwas davon lief, in Millisekunden seit 1970.
    var lastWatched: Double?

    init(
        state: WatchState,
        ratio: Double,
        season: String? = nil,
        episode: Int? = nil,
        completedEpisodes: Int = 0,
        lastWatched: Double? = nil
    ) {
        self.state = state
        self.ratio = ratio
        self.season = season
        self.episode = episode
        self.completedEpisodes = completedEpisodes
        self.lastWatched = lastWatched
    }

    static let none = WatchSummary(state: .unseen, ratio: 0)

    /// Der Wert, nach dem „Fortschritt" sortiert.
    ///
    /// Nicht `ratio` allein: wer in Folge 40 bei 10 % steht, ist weiter als
    /// jemand bei 90 % der ersten Folge, und eine Sortierung, die das
    /// umdreht, sieht aus wie ein Fehler. Die Zahl der abgeschlossenen Folgen
    /// führt deshalb, der Stand in der laufenden entscheidet innerhalb davon.
    var sortValue: Double { Double(completedEpisodes) + min(max(ratio, 0), 1) }

    /// Die Zeile unter dem Titel, so wie sie in der Vorlage steht.
    var stateText: String {
        switch state {
        case .unseen:
            return "Noch nicht begonnen"
        case .seen:
            return "Komplett gesehen"
        case .started:
            let percent = Int((ratio * 100).rounded())
            guard let season, let episode else { return "Angefangen · \(percent) %" }
            return "\(seasonLabel(season)) · F\(episode) · \(percent) %"
        }
    }

    /// „S1", oder „Filme" für die Sonderstaffel beider Quellen.
    private func seasonLabel(_ season: String) -> String {
        season == "filme" ? "Filme" : "S\(season)"
    }
}

/// Den Stand eines Titels aus seinem Fortschritt herleiten.
///
/// `entries` sind **alle** Einträge zu diesem Titel und dieser Quelle; die
/// Auswahl trifft der Aufrufer, weil derselbe Slug bei AniWorld und
/// Serienstream stehen kann und die beiden Stände einander nicht
/// überschreiben dürfen.
///
/// „Gesehen" heißt hier: jede Folge, die Nori von diesem Titel kennt, ist
/// abgeschlossen — und er kennt mindestens eine. Mehr ist ohne die
/// Folgenliste der Quelle nicht zu behaupten, und das Gegenteil zu behaupten
/// wäre schlechter: ein Titel, dessen sämtliche geöffneten Folgen durch sind,
/// als „angefangen" zu führen, macht den Filter „Gesehen" dauerhaft leer.
func watchSummary(for entries: [WatchProgress]) -> WatchSummary {
    // Ein Eintrag mit Position 0 und ohne Abschluss entsteht schon beim
    // bloßen Öffnen einer Folge. Er ist kein „angefangen".
    let touched = entries.filter { $0.positionSec > 0 || $0.completed == true }
    guard !touched.isEmpty else { return .none }

    let completed = touched.filter { isEpisodeComplete($0) }
    let latest = touched.max { $0.updatedAt < $1.updatedAt }
    let lastWatched = latest?.updatedAt

    if completed.count == touched.count {
        return WatchSummary(
            state: .seen,
            ratio: 1,
            season: latest?.season,
            episode: latest?.episode,
            completedEpisodes: completed.count,
            lastWatched: lastWatched
        )
    }

    // Der Balken zeigt die Folge, in der zuletzt etwas lief — auch dann,
    // wenn sie schon durch ist und nur die Folge danach noch aussteht. Eine
    // beliebige offene Folge dafür zu suchen, führte zu Sprüngen, die zu
    // nichts gehören, was jemand zuletzt getan hat.
    let current = latest.flatMap { isEpisodeComplete($0) ? nil : $0 }
        ?? touched.filter { !isEpisodeComplete($0) }.max { $0.updatedAt < $1.updatedAt }

    return WatchSummary(
        state: .started,
        ratio: watchRatio(current),
        season: current?.season ?? latest?.season,
        episode: current?.episode ?? latest?.episode,
        completedEpisodes: completed.count,
        lastWatched: lastWatched
    )
}

// MARK: - Setzen

/// Millisekunden seit 1970 — das Zeitformat aller Bibliotheksdaten.
func nowMillis() -> Double { Date().timeIntervalSince1970 * 1000 }

/// Welcher Titel, welche Staffel, welche Quelle.
struct MarkTarget: Hashable {
    var slug: String
    var title: String
    var season: String
    var provider: CatalogProvider

    init(slug: String, title: String, season: String, provider: CatalogProvider) {
        self.slug = slug
        self.title = title
        self.season = season
        self.provider = provider
    }
}

/// Eine Staffel mit ihren Folgen — für „ganze Serie".
struct SeasonEpisodes: Hashable {
    var season: String
    var episodes: [Episode]

    init(season: String, episodes: [Episode]) {
        self.season = season
        self.episodes = episodes
    }
}

enum WatchMarks {
    /// Alle Fortschrittseinträge eines Titels bei einer Quelle.
    static func entries(
        in progress: [String: WatchProgress],
        slug: String,
        provider: CatalogProvider
    ) -> [WatchProgress] {
        progress.values.filter {
            $0.slug == slug && ($0.provider ?? providerFromPath($0.episodePath)) == provider
        }
    }

    /// Der Stand eines Titels, direkt aus der Ablage.
    static func summary(
        in progress: [String: WatchProgress],
        slug: String,
        provider: CatalogProvider
    ) -> WatchSummary {
        watchSummary(for: entries(in: progress, slug: slug, provider: provider))
    }

    /// Wie viele Folgen eines Titels abgeschlossen sind, über alle Staffeln.
    static func completedCount(
        in progress: [String: WatchProgress],
        slug: String,
        provider: CatalogProvider
    ) -> Int {
        entries(in: progress, slug: slug, provider: provider).filter { isEpisodeComplete($0) }.count
    }

    // MARK: - Setzen

    /// Eine Folge als gesehen oder ungesehen markieren.
    ///
    /// Eine bekannte Laufzeit bleibt stehen: sie beim Abhaken auf null zu
    /// setzen wäre ein Verlust, und beim Zurücksetzen brauchte die Folge sie
    /// sofort wieder, sobald jemand sie erneut abspielt.
    static func episode(
        in progress: [String: WatchProgress],
        target: MarkTarget,
        episode: Episode,
        seen: Bool,
        now: Double = nowMillis()
    ) -> WatchProgress {
        let known = existingEntry(in: progress, target: target, episode: episode)
        let duration = known?.durationSec ?? 0
        return WatchProgress(
            slug: target.slug,
            title: target.title,
            season: target.season,
            episode: episode.number,
            episodePath: episode.path,
            germanTitle: episode.germanTitle,
            englishTitle: episode.englishTitle,
            positionSec: seen ? duration : 0,
            durationSec: duration,
            updatedAt: now,
            lang: known?.lang,
            completed: seen,
            provider: target.provider
        )
    }

    /// Eine ganze Staffel auf einmal.
    static func season(
        in progress: [String: WatchProgress],
        target: MarkTarget,
        episodes: [Episode],
        seen: Bool,
        now: Double = nowMillis()
    ) -> [WatchProgress] {
        episodes.map { episode(in: progress, target: target, episode: $0, seen: seen, now: now) }
    }

    /// Eine ganze Serie als gesehen markieren.
    ///
    /// Braucht die Folgenlisten aller Staffeln; die holt der Aufrufer, weil nur
    /// er weiß, was schon geladen ist und was erst noch über das Netz kommt.
    /// Der umgekehrte Weg — „Serie als ungesehen" — kommt mit
    /// `resetSeries` ohne Netz aus.
    static func series(
        in progress: [String: WatchProgress],
        slug: String,
        title: String,
        provider: CatalogProvider,
        seasons: [SeasonEpisodes],
        seen: Bool,
        now: Double = nowMillis()
    ) -> [WatchProgress] {
        var out: [WatchProgress] = []
        for entry in seasons {
            let target = MarkTarget(slug: slug, title: title, season: entry.season, provider: provider)
            for item in entry.episodes {
                out.append(episode(in: progress, target: target, episode: item, seen: seen, now: now))
            }
        }
        return out
    }

    /// Jeden bekannten Fortschritt einer Serie zurücksetzen — ohne Folgenliste.
    ///
    /// Das ist „Serie als ungesehen" und zugleich „Fortschritt vergessen": was
    /// Nori nicht kennt, ist ohnehin ungesehen, und was es kennt, wird auf null
    /// gesetzt statt gelöscht (siehe Kopf dieser Datei).
    static func resetSeries(
        in progress: [String: WatchProgress],
        slug: String,
        provider: CatalogProvider,
        now: Double = nowMillis()
    ) -> [WatchProgress] {
        entries(in: progress, slug: slug, provider: provider)
            .filter { $0.positionSec > 0 || $0.completed == true }
            .map { reset($0, now: now) }
    }

    /// Eine einzelne Staffel vergessen, ohne die übrigen anzurühren.
    static func resetSeason(
        in progress: [String: WatchProgress],
        slug: String,
        season: String,
        provider: CatalogProvider,
        now: Double = nowMillis()
    ) -> [WatchProgress] {
        entries(in: progress, slug: slug, provider: provider)
            .filter { $0.season == season && ($0.positionSec > 0 || $0.completed == true) }
            .map { reset($0, now: now) }
    }

    /// „Aus Weiterschauen entfernen".
    ///
    /// Nur die angefangenen Einträge der Serie werden zurückgesetzt —
    /// abgeschlossene Folgen bleiben abgeschlossen. Die Reihe sucht sich je
    /// Serie den jüngsten unfertigen Eintrag (`continueWatching`); ist keiner
    /// mehr übrig, verschwindet die Serie dort, ohne dass jemand „gesehen"
    /// verliert.
    static func removeFromContinueWatching(
        in progress: [String: WatchProgress],
        slug: String,
        provider: CatalogProvider,
        now: Double = nowMillis()
    ) -> [WatchProgress] {
        entries(in: progress, slug: slug, provider: provider)
            .filter { !isEpisodeComplete($0) && $0.positionSec > 0 }
            .map { reset($0, now: now) }
    }

    /// Einen Eintrag auf „nie angefasst" setzen, Laufzeit und Sprache behalten.
    static func reset(_ item: WatchProgress, now: Double = nowMillis()) -> WatchProgress {
        var next = item
        next.positionSec = 0
        next.completed = false
        next.updatedAt = now
        return next
    }

    // MARK: - Intern

    private static func existingEntry(
        in progress: [String: WatchProgress],
        target: MarkTarget,
        episode: Episode
    ) -> WatchProgress? {
        if let direct = progress[progressKey(path: episode.path, provider: target.provider)] { return direct }
        for item in progress.values {
            guard item.slug == target.slug, item.season == target.season, item.episode == episode.number else { continue }
            guard (item.provider ?? providerFromPath(item.episodePath)) == target.provider else { continue }
            return item
        }
        return nil
    }
}

/// „7 von 12 gesehen" — oder nichts, wenn es nichts zu sagen gibt.
func seasonProgressLabel(watched: Int, total: Int) -> String? {
    guard total > 0, watched > 0 else { return nil }
    return "\(watched) von \(total) gesehen"
}

// MARK: - Bequeme Aufrufe an der Bibliothek

extension LibraryStore {
    /// Der Sehstand eines Titels — dieselbe Regel wie in der Merkliste.
    ///
    /// Bewusst nicht `watchSummary`: die freie Funktion dieses Namens steht in
    /// `WatchlistModel.swift` und wird aus einer anderen `LibraryStore`-
    /// Erweiterung heraus aufgerufen. Ein gleichnamiges Mitglied verdeckt sie
    /// dort, und der Fehler entstünde an einer Stelle, die niemand angefasst
    /// hat.
    func seriesWatchSummary(slug: String, provider: CatalogProvider? = nil) -> WatchSummary {
        WatchMarks.summary(in: progress, slug: slug, provider: provider ?? self.provider)
    }

    /// Eine Folge abhaken oder wieder freigeben.
    func setWatched(
        _ seen: Bool,
        slug: String,
        title: String,
        season: String,
        episode: Episode,
        provider: CatalogProvider? = nil
    ) {
        let target = MarkTarget(slug: slug, title: title, season: season, provider: provider ?? self.provider)
        upsert(contentsOf: [WatchMarks.episode(in: progress, target: target, episode: episode, seen: seen)])
    }

    /// Eine ganze Staffel — ein Schreibvorgang, nicht einer je Folge.
    func setSeasonWatched(
        _ seen: Bool,
        slug: String,
        title: String,
        season: String,
        episodes: [Episode],
        provider: CatalogProvider? = nil
    ) {
        guard !episodes.isEmpty else { return }
        let target = MarkTarget(slug: slug, title: title, season: season, provider: provider ?? self.provider)
        upsert(contentsOf: WatchMarks.season(in: progress, target: target, episodes: episodes, seen: seen))
    }

    /// Eine ganze Serie als gesehen — die Folgenlisten holt der Aufrufer.
    func setSeriesWatched(
        slug: String,
        title: String,
        seasons: [SeasonEpisodes],
        provider: CatalogProvider? = nil
    ) {
        let source = provider ?? self.provider
        let items = WatchMarks.series(
            in: progress, slug: slug, title: title, provider: source, seasons: seasons, seen: true
        )
        upsert(contentsOf: items)
    }

    /// Jeden bekannten Fortschritt einer Serie zurücksetzen.
    func resetSeriesProgress(slug: String, provider: CatalogProvider? = nil) {
        upsert(contentsOf: WatchMarks.resetSeries(in: progress, slug: slug, provider: provider ?? self.provider))
    }

    /// Nur eine Staffel vergessen.
    func resetSeasonProgress(slug: String, season: String, provider: CatalogProvider? = nil) {
        upsert(contentsOf: WatchMarks.resetSeason(
            in: progress, slug: slug, season: season, provider: provider ?? self.provider
        ))
    }

    /// Eine Serie aus „Weiterschauen" nehmen, ohne „gesehen" zu verlieren.
    func removeFromContinueWatching(slug: String, provider: CatalogProvider? = nil) {
        upsert(contentsOf: WatchMarks.removeFromContinueWatching(
            in: progress, slug: slug, provider: provider ?? self.provider
        ))
    }
}
