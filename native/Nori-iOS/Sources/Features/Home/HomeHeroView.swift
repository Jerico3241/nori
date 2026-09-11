import SwiftUI

/// Der Kopfbereich der Startseite.
///
/// Ein einzelnes, großes Artwork über rund drei Viertel des Bildschirms, mit
/// Schriftzug, Eckdaten, Beschreibung und drei Knöpfen darauf. Das ist der
/// wesentliche Unterschied zur vorherigen Startseite, deren Kopfbereich ein
/// blätterbarer Streifen mit Titel und zwei Knöpfen war.
///
/// ## Warum kein Karussell mehr
///
/// Ein `TabView` im Seitenstil innerhalb des senkrechten Scrollbereichs ist
/// verschachteltes Scrollen: zwei Gestenerkenner, die sich um dieselbe
/// Bewegung streiten. Der Kopfbereich zeigt stattdessen **einen** Titel, der
/// sich täglich ändert (`HomeRanking.heroPicks` dreht die Auswahl über den
/// Tag) und über „Mehr › Nächster Vorschlag" auch von Hand weiterrückt.
///
/// ## Warum das Bild über den Bildschirmrand läuft
///
/// Der Kopfbereich soll nicht wie ein Banner auf der Seite liegen, sondern
/// die Seite anfangen. Das Artwork läuft deshalb unter Statusleiste und
/// Navigationsleiste durch; Schriftzug, Text und Knöpfe bleiben innerhalb der
/// Sicherheitszone. Der Verlauf am unteren Rand endet in `NoriTheme.bg` —
/// nicht in Schwarz —, damit es zwischen Bild und Inhalt keine Kante gibt.
struct HomeHeroView: View {
    let candidate: HomeCandidate
    let height: CGFloat
    /// Höhe der oberen Sicherheitszone. Kommt von außen, weil der
    /// Scrollbereich sie ignoriert und sie hier drin nicht mehr messbar ist.
    let topInset: CGFloat
    /// Gibt es mehr als einen Vorschlag? Steuert nur den Menüeintrag.
    var canAdvance: Bool = false
    let onSearch: () -> Void
    let onNext: () -> Void
    let onPlay: () -> Void

    @Environment(LibraryStore.self) private var library
    @NoriReduceMotion private var reduceMotion
    /// „Dynamische Farben" aus „Mehr → Darstellung": ob die Farbe des Artworks
    /// den Kopfbereich einfärben darf.
    @AppStorage(NoriLook.dynamicColorsKey) private var dynamicColors = true

    @State private var details = CoverDetails(poster: nil, backdrop: nil, overview: nil, rating: nil)
    @State private var logo: URL?
    /// Die vorherrschende Farbe des Artworks. Trägt den Schimmer hinter dem
    /// Bild — dieselbe Sprache wie auf der Detailseite.
    @State private var tone: Color?
    /// Läuft die Serie gerade an? Der Knopf braucht die Detailseite, bevor
    /// feststeht, welche Folge überhaupt gemeint ist.
    var preparing: Bool = false

    private var artwork: URL? { details.backdrop ?? details.poster }

    var body: some View {
        ZStack(alignment: .bottom) {
            backdrop
            shade
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 12)
                copy
            }
            .padding(.top, topInset + 6)
            .padding(.horizontal, HomeMetrics.screen)
            .padding(.bottom, 26)
        }
        .frame(height: height)
        .task(id: candidate.id) { await loadArt() }
        .task(id: artwork) { await sampleTone() }
    }

    // MARK: - Bild

    /// Das Artwork, formatfüllend und oben verankert.
    ///
    /// Oben verankert, weil auf einem Breitbild das Motiv selten unten sitzt
    /// und ein Poster seinen Schriftzug im oberen Drittel trägt. Mittig
    /// zugeschnitten wäre auf einem so hohen Rahmen regelmäßig der Kopf der
    /// Figur weg.
    @ViewBuilder
    private var backdrop: some View {
        if let artwork {
            NoriAnchoredImage(
                url: artwork,
                referer: HomeArtwork.referer(for: artwork, provider: candidate.title.provider),
                verticalAnchor: 0.16
            ) {
                NoriTheme.elevated
            }
        } else {
            NoriTheme.elevated
        }
    }

    /// Zwei Lagen über dem Bild.
    ///
    /// 1. Ein Schimmer in der abgetasteten Coverfarbe, oben rechts — dieselbe
    ///    Stelle wie auf der Vorlage. Er färbt den Kopfbereich, ohne dass das
    ///    Artwork eingefärbt würde.
    /// 2. Der Verlauf nach unten in Noris Hintergrundfarbe. Er trägt die
    ///    Schrift: ohne ihn steht weißer Text auf einem beliebig hellen Bild.
    private var shade: some View {
        ZStack {
            RadialGradient(
                colors: [(tone ?? NoriTheme.accent).opacity(0.32), .clear],
                center: UnitPoint(x: 0.74, y: 0.18),
                startRadius: 0,
                endRadius: height * 0.55
            )
            .blendMode(.plusLighter)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.28), location: 0),
                    .init(color: .clear, location: 0.24),
                    .init(color: NoriTheme.bg.opacity(0.34), location: 0.46),
                    .init(color: NoriTheme.bg.opacity(0.88), location: 0.76),
                    .init(color: NoriTheme.bg, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    // MARK: - Kopfzeile

    /// Marke und Suche.
    ///
    /// Nur der Schriftzug, kein Bildzeichen: die Vorlage setzt links ein
    /// Kästchen mit einem „の" davor, aber das ist eine Erfindung des
    /// Entwurfs — Nori hat kein solches Logo. Ein Zeichen zu zeichnen, das
    /// die App gar nicht führt, wäre eine Marke, die es nicht gibt.
    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Nori")
                .font(.system(size: 25, weight: .heavy))
                .foregroundStyle(NoriTheme.fg)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 1)
            Spacer(minLength: 8)
            searchButton
        }
    }

    /// Öffnet Noris vorhandene Suche.
    ///
    /// Sie liegt im Katalog-Tab, als `searchable` an dessen Navigationsleiste.
    /// Der Knopf wechselt deshalb dorthin, statt auf der Startseite ein
    /// zweites Suchfeld aufzubauen — eine zweite Suche wäre eine zweite
    /// Filterlogik, die mit der ersten auseinanderlaufen kann.
    private var searchButton: some View {
        Button(action: onSearch) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NoriTheme.fg)
                .frame(width: 46, height: 46)
        }
        .buttonStyle(NoriPressStyle(scale: 0.9))
        .background { HomeGlassCircle() }
        .accessibilityLabel("Suchen")
    }

    // MARK: - Text und Knöpfe

    /// Kicker, Schriftzug, Eckdaten, Beschreibung, Knöpfe.
    ///
    /// Die Abstände stehen einzeln statt als ein gemeinsames `spacing`, weil
    /// der Schriftzug zwei sehr verschiedene Formen hat. Als **Text** ist er
    /// randlos und braucht oben und unten Luft. Als **TMDB-Logo** ist er ein
    /// PNG, und die bringen durchweg einen durchsichtigen Rand mit — bei
    /// gleichem `spacing` steht der Kicker dann rund vierzig statt zehn Punkte
    /// über dem Schriftzug und sieht aus, als gehöre er nicht dazu.
    private var copy: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Heute im Fokus")
                .font(.system(size: 13, weight: .bold))
                .kerning(1.1)
                .textCase(.uppercase)
                .foregroundStyle(NoriTheme.fg.opacity(0.72))

            titleArt
                .padding(.top, logo == nil ? 8 : 0)

            HomeHeroMeta(candidate: candidate, stars: details.stars)
                .padding(.top, logo == nil ? 10 : 0)

            if let text = overview {
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(NoriTheme.fg.opacity(0.82))
                    .lineSpacing(3)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            actions
                .padding(.top, 18)
        }
        .frame(maxWidth: SeriesMetrics.reading, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overview: String? {
        let text = details.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Der Schriftzug — das TMDB-Logo, sonst der Titel als Text.
    ///
    /// Der Rückfall ist der Normalfall, nicht die Ausnahme: die wenigsten
    /// Serien haben bei TMDB ein freigestelltes Logo. Deshalb ist der Text
    /// gestaltet und nicht bloß groß — Serifen und ein Schimmer in der
    /// Coverfarbe, genau wie auf der Detailseite.
    @ViewBuilder
    private var titleArt: some View {
        if let logo {
            // `AsyncImage` statt `NoriAnchoredImage`: ein freigestellter
            // Schriftzug soll eingepasst werden, nicht formatfüllend
            // zugeschnitten. TMDB braucht dafür keine Kopfzeilen.
            AsyncImage(url: logo) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            // Mittig im Kasten und der Kasten knapp gehalten: ein
            // TMDB-Logo ist ein PNG mit durchsichtigem Rand, und der bleibt
            // als Leerraum stehen. Unten bündig verteilte ihn vollständig
            // nach oben — dann klebte die Eckdatenzeile am Schriftzug.
            // Mittig teilt er sich gleichmäßig, und bei 92 Punkten Kastenhöhe
            // bleiben davon auf jeder Seite rund zwanzig übrig.
            .frame(maxWidth: 300, maxHeight: 92, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 3)
            .accessibilityLabel(candidate.title.title)
        } else {
            Text(candidate.title.title)
                .font(.system(size: 44, weight: .bold, design: .serif))
                .foregroundStyle(NoriTheme.fg)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 2)
                .shadow(color: (tone ?? NoriTheme.accent).opacity(0.26), radius: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Die drei Knöpfe.
    ///
    /// Nicht zu gleichen Teilen: die Vorlage gibt dem Abspielknopf ein gutes
    /// Drittel mehr Breite als dem Merklisten-Knopf (1,25 zu 0,95), und das
    /// ist keine Kosmetik. „Jetzt ansehen" ist mit Symbol und Beschriftung
    /// deutlich breiter als „Merkliste"; bei gleicher Aufteilung lief der Text
    /// bis an die Kapselkante und wurde von `minimumScaleFactor` kleiner
    /// gezogen, während daneben Platz frei blieb.
    private var actions: some View {
        let gaps: CGFloat = 18
        let free = max(0, actionRowWidth - HomeMetrics.actionSquare - gaps)
        let total: CGFloat = 1.25 + 0.95
        return HStack(spacing: 9) {
            HomeHeroPlayButton(candidate: candidate, preparing: preparing, action: onPlay)
                .frame(width: free * 1.25 / total)
            HomeHeroWatchlistButton(candidate: candidate, tone: tone)
                .frame(width: free * 0.95 / total)
            moreButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Die Breite, die der Knopfreihe tatsächlich zur Verfügung steht.
    ///
    /// Aus dem Fenster gerechnet statt gemessen: ein `GeometryReader` um die
    /// Reihe herum würde seine Höhe an die Umgebung abgeben und den Stapel
    /// darüber auseinanderziehen. Die Rechnung ist dieselbe wie die des
    /// Textblocks — Seitenrand links und rechts, gedeckelt auf die Lesebreite.
    private var actionRowWidth: CGFloat {
        min(NoriScreenMetrics.size.width - HomeMetrics.screen * 2, SeriesMetrics.reading)
    }

    /// Das Überlaufmenü. Zwei Einträge, und beide tun etwas, was die drei
    /// Knöpfe nicht können.
    private var moreButton: some View {
        Menu {
            NavigationLink {
                SeriesView(
                    slug: candidate.title.slug,
                    titleHint: candidate.title.title,
                    providerOverride: candidate.title.provider
                )
            } label: {
                Label("Zur Serie", systemImage: "info.circle")
            }
            if canAdvance {
                Button {
                    onNext()
                } label: {
                    Label("Nächster Vorschlag", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(NoriTheme.fg)
                .frame(width: HomeMetrics.actionSquare, height: HomeMetrics.action)
                .background { HomeGlassCapsule() }
        }
        .accessibilityLabel("Weitere Aktionen")
    }

    // MARK: - Laden

    private func loadArt() async {
        details = await CoverIndex.shared.detailsLoading(
            slug: candidate.title.slug,
            title: candidate.title.title,
            kind: candidate.title.provider
        )
        // Ohne TMDB-Treffer hätte der Kopfbereich weder Breitbild noch Poster
        // und bliebe eine graue Fläche. Das Cover der Quelle ist immer das
        // richtige, es steht nur auf der Detailseite.
        if details.backdrop == nil, details.poster == nil {
            details.poster = await CoverIndex.shared.fetchSourceCover(
                slug: candidate.title.slug,
                provider: candidate.title.provider
            )
        }
        guard !Task.isCancelled else { return }
        logo = await CoverIndex.shared.logoLoading(
            slug: candidate.title.slug,
            title: candidate.title.title,
            alternates: candidate.title.alts,
            kind: candidate.title.provider
        )
    }

    private func sampleTone() async {
        // „Dynamische Farben" aus „Mehr → Darstellung". Aus heißt: die Farbe
        // wird nicht einmal abgetastet — sonst liefe der Abruf weiter und nur
        // das Ergebnis bliebe ungenutzt.
        guard dynamicColors else {
            tone = nil
            return
        }
        guard let artwork else {
            tone = nil
            return
        }
        let sampled = await CoverToneSampler.sample(url: artwork)
        guard !Task.isCancelled else { return }
        let next = sampled?.noriReadableAccent()
        if reduceMotion {
            tone = next
        } else {
            withAnimation(NoriMotion.content) { tone = next }
        }
    }
}

// MARK: - Eckdaten

/// Jahr, Genres und Bewertung in einer fortlaufenden Zeile.
///
/// Eigene Ansicht, weil `Text`-Verkettung mit unterschiedlichen Farben den
/// Typechecker im umgebenden `ViewBuilder` sonst überfordert — dieselbe
/// Erfahrung wie auf der Detailseite. Was fehlt, fällt samt Trenner weg; eine
/// erfundene Angabe gibt es nicht.
struct HomeHeroMeta: View {
    let candidate: HomeCandidate
    let stars: Double?

    private var parts: [String] {
        var out: [String] = []
        if let date = candidate.signals.firstAirDate {
            out.append(String(Calendar.current.component(.year, from: date)))
        }
        out.append(contentsOf: candidate.title.genres.prefix(2).filter { !$0.isEmpty })
        return out
    }

    var body: some View {
        let joined = parts.joined(separator: "\u{00A0}·  ")
        var line = Text(joined)
        if let stars {
            if !joined.isEmpty { line = line + Text("\u{00A0}·  ") }
            line = line + Text("★").foregroundStyle(.yellow)
            line = line + Text(" " + String(format: "%.1f", stars))
        }
        return line
            .font(.system(size: 15))
            .foregroundStyle(NoriTheme.fg.opacity(0.94))
            .lineSpacing(3)
            .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var text = parts.joined(separator: ", ")
        if let stars { text += ", Bewertung \(String(format: "%.1f", stars)) von 5" }
        return text
    }
}

// MARK: - Knöpfe

/// „Jetzt ansehen" beziehungsweise „Weiter ansehen".
///
/// Eigene Ansicht, weil sie den Fortschritt liest: so zeichnet bei einer
/// Änderung nur der Knopf neu und nicht der Kopfbereich mitsamt Artwork.
/// Welche Folge dann startet, entscheidet `nextPlay` im Kern — dieselbe Regel
/// wie auf der Detailseite und in „Weiterschauen", damit alle drei Wege in
/// derselben Folge landen.
struct HomeHeroPlayButton: View {
    @Environment(LibraryStore.self) private var library
    let candidate: HomeCandidate
    let preparing: Bool
    let action: () -> Void

    private var resuming: Bool {
        HomePlayback.startedSeason(for: candidate.title, in: library) != nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if preparing {
                    ProgressView().tint(NoriTheme.bg)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                }
                Text(resuming ? "Weiter ansehen" : "Jetzt ansehen")
                    .font(.system(size: 16, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(NoriTheme.bg)
            // Innenabstand, damit die Beschriftung die Kapselkante nie
            // berührt — auch nicht bei „Weiter ansehen", das ein Zeichen
            // länger ist als „Jetzt ansehen".
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: HomeMetrics.action)
            .background {
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.99, blue: 1), Color(red: 0.86, green: 0.91, blue: 0.965)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
        }
        .buttonStyle(NoriPressStyle(scale: 0.97))
        .disabled(preparing)
        .accessibilityLabel(resuming ? "\(candidate.title.title) weiterschauen" : "\(candidate.title.title) ansehen")
    }
}

/// Der Merklisten-Knopf des Kopfbereichs.
///
/// Benutzt `LibraryStore` — es gibt in Nori genau eine Merkliste, und die
/// Startseite legt keine zweite an.
struct HomeHeroWatchlistButton: View {
    @Environment(LibraryStore.self) private var library
    let candidate: HomeCandidate
    let tone: Color?

    @AppStorage(NoriGlassSetting.key) private var glass = true

    var body: some View {
        let marked = library.isFavorite(candidate.title.slug)
        Button {
            library.toggleFavorite(candidate.title.slug, title: candidate.title.title)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: marked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(marked ? "Gemerkt" : "Merkliste")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(NoriTheme.fg)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: HomeMetrics.action)
            .noriGlass(
                Capsule(),
                enabled: glass,
                tint: marked ? (tone ?? NoriTheme.accent).opacity(0.35) : nil,
                off: NoriTheme.elevated.opacity(0.9)
            )
            .overlay { Capsule().strokeBorder(.white.opacity(glass ? 0 : 0.16)) }
        }
        .buttonStyle(NoriPressStyle(scale: 0.97))
        .noriHaptic(.selection, trigger: marked)
        .accessibilityLabel(marked ? "Aus der Merkliste entfernen" : "Zur Merkliste hinzufügen")
    }
}

// MARK: - Glas

/// Runder Glasgrund für die Symboltasten der Kopfzeile.
struct HomeGlassCircle: View {
    @AppStorage(NoriGlassSetting.key) private var glass = true

    var body: some View {
        Color.clear
            .noriGlass(Circle(), enabled: glass, off: Color.white.opacity(0.16))
            .overlay { Circle().strokeBorder(.white.opacity(glass ? 0 : 0.18)) }
    }
}

/// Kapselförmiger Glasgrund — für den „Mehr"-Knopf.
struct HomeGlassCapsule: View {
    @AppStorage(NoriGlassSetting.key) private var glass = true

    var body: some View {
        Color.clear
            .noriGlass(Capsule(), enabled: glass, off: NoriTheme.elevated.opacity(0.9))
            .overlay { Capsule().strokeBorder(.white.opacity(glass ? 0 : 0.16)) }
    }
}
