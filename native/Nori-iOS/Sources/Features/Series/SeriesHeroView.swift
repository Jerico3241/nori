import SwiftUI

// Der Kopfbereich der Detailseite: Artwork, Schriftzug, Eckdaten,
// Beschreibung, die beiden Knöpfe.
//
// Alles davon steht **auf** dem Bild, nicht darunter — das ist der
// wesentliche Unterschied zur vorherigen Detailseite, auf der ein kleines
// Poster neben einer Textspalte stand. Der Inhalt bestimmt die Höhe, das Bild
// nimmt sie an.

struct SeriesHeroView: View {
    let detail: SeriesDetail
    let artwork: SeriesArtwork
    let tone: Color?
    let logo: URL?
    let stars: Double?
    /// Beschreibung von TMDB. Nur Rückfall — die Quelle beschreibt die meisten
    /// Titel selbst, und ihr Text ist der, den der Katalog zeigt.
    let overview: String?
    let season: String
    let provider: CatalogProvider
    /// Maße des Fensters. Bestimmen Höhe des Artworks, Schriftgröße des
    /// Titels und die Breite, ab der der Text nicht weiter mitwächst.
    let screen: CGSize
    let play: (Episode, Double) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Color.clear.frame(height: topSpace)

            titleArt

            if let tagline {
                Text(tagline)
                    .font(.callout.italic())
                    .foregroundStyle(NoriTheme.muted)
                    .lineLimit(2)
                    .padding(.top, -4)
            }

            metaLine

            synopsis

            actions
                .padding(.top, 4)
        }
        // Der Text hört auf mitzuwachsen, das Bild nicht: auf einem iPad
        // läuft eine Beschreibung über 1000 Punkte Breite nicht mehr lesbar,
        // ein Kopfbild über dieselbe Breite dagegen schon. Die Spalte ist
        // dieselbe wie die der Folgenliste darunter — sonst begänne die
        // Beschreibung links neben den Karten.
        // Erst der Seitenrand, dann der Deckel: die Folgenliste darunter
        // rechnet genauso, und nur so beginnen Text und Karten auf derselben
        // Linie.
        .padding(.horizontal, NoriSpacing.screen)
        .frame(maxWidth: SeriesMetrics.content)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
        .background { SeriesBackdrop(artwork: artwork, tone: tone, screen: screen) }
    }

    /// Wie weit der Schriftzug vom oberen Rand absteht.
    ///
    /// Gemessen am scharfen Streifen, nicht am Bildschirm: der Titel beginnt
    /// erst dort, wo der Streifen schon fast ausgeblendet ist. Weiter oben
    /// stünde er auf dem Bild statt darunter — und bei einem Cover mit
    /// eingebranntem Schriftzug stünde dessen Titel blass hinter dem echten.
    /// Die Untergrenze hält ihn von der Navigationsleiste frei, auch wenn ein
    /// Gerät sehr schmal ist.
    private var topSpace: CGFloat {
        max(artwork.bandHeight(in: screen) * 0.78, 150)
    }

    /// Lesebreite für Fließtext. Schmaler als die Spalte: eine Zeile über die
    /// volle iPad-Breite liest sich nicht mehr.
    private var readingWidth: CGFloat { min(screen.width, SeriesMetrics.reading) }

    /// Schriftzug aus TMDB, sonst der Titel als Text.
    ///
    /// Der Text ist der Normalfall, nicht die Ausnahme — die wenigsten Serien
    /// haben bei TMDB einen freigestellten Schriftzug. Deshalb ist er
    /// gestaltet und nicht bloß groß: Serifen, weit gesetzt, mit einem
    /// Schimmer in der Coverfarbe.
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
            .frame(maxWidth: readingWidth * 0.8, maxHeight: 112, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 3)
            .accessibilityLabel(detail.title)
        } else {
            Text(detail.title)
                .font(.system(size: titleSize, weight: .bold, design: .serif))
                .foregroundStyle(NoriTheme.fg)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.leading)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 2)
                .shadow(color: (tone ?? NoriTheme.accent).opacity(0.28), radius: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleSize: CGFloat {
        min(max(screen.width * 0.125, 30), 52)
    }

    /// Die Zeile unter dem Schriftzug.
    ///
    /// Der erste Alternativtitel — bei Anime meist die japanische oder
    /// englische Fassung. Steht dort dasselbe noch einmal, entfällt die Zeile;
    /// eine erfundene Zeile gibt es nicht.
    private var tagline: String? {
        guard let first = detail.alts.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !first.isEmpty,
              first.caseInsensitiveCompare(detail.title) != .orderedSame
        else { return nil }
        return first
    }

    /// Jahr, Genres, Staffelzahl, Stand, Bewertung — in einer fortlaufenden
    /// Zeile. Was fehlt, fällt samt Trenner weg.
    private var metaLine: some View {
        var parts: [String] = []
        if let year = detail.yearStart?.trimmingCharacters(in: .whitespacesAndNewlines), !year.isEmpty {
            parts.append(year)
        }
        parts.append(contentsOf: detail.genres.prefix(3).filter { !$0.isEmpty })
        if !detail.seasons.isEmpty {
            parts.append(detail.seasons.count == 1 ? "1 Staffel" : "\(detail.seasons.count) Staffeln")
            parts.append((detail.yearEnd?.isEmpty == false) ? "Beendet" : "Laufend")
        }

        // Geschütztes Leerzeichen vor dem Trenner: sonst rutscht beim Umbruch
        // ein „·" allein an den Anfang der zweiten Zeile.
        var line = Text(parts.joined(separator: "\u{00A0}·  "))
        if let stars {
            if !parts.isEmpty { line = line + Text("\u{00A0}·  ") }
            line = line
                + Text("★").foregroundStyle(.yellow)
                + Text(" " + String(format: "%.1f", stars))
        }

        return line
            .font(.subheadline)
            .foregroundStyle(NoriTheme.fg.opacity(0.92))
            .lineSpacing(3)
            .frame(maxWidth: readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(accessibleMeta(parts))
    }

    private func accessibleMeta(_ parts: [String]) -> String {
        var text = parts.joined(separator: ", ")
        if let stars { text += ", Bewertung \(String(format: "%.1f", stars)) von 5" }
        return text
    }

    /// Die Beschreibung, ohne eigenen Reiter.
    ///
    /// Sie stand früher hinter „Details" und war damit auf einer Detailseite
    /// einen Tipp entfernt. Auf kleinen Geräten bleiben vier Zeilen stehen,
    /// der Rest hängt an „Mehr anzeigen" — ohne dass der Knopf erscheint, wo
    /// es gar nichts aufzuklappen gibt.
    @ViewBuilder
    private var synopsis: some View {
        if let text = descriptionText {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(NoriTheme.fg.opacity(0.82))
                    .lineSpacing(3)
                    .lineLimit(expanded ? nil : 4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if text.count > 190 {
                    Button(expanded ? "Weniger anzeigen" : "Mehr anzeigen") {
                        withAnimation(NoriMotion.micro) { expanded.toggle() }
                    }
                    .font(.subheadline.weight(.semibold))
                    // Weiß statt Coverfarbe: eine abgetastete Farbe kann
                    // gedeckt ausfallen, und ein Textknopf in Ocker auf
                    // Fastschwarz ist schwer zu lesen. Die Farbe trägt die
                    // Seite an Flächen, nicht an Schrift.
                    .foregroundStyle(NoriTheme.fg)
                }
            }
            .frame(maxWidth: readingWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var descriptionText: String? {
        let own = detail.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        let other = overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return other.isEmpty ? nil : other
    }

    /// Abspielen und merken — die einzigen beiden Knöpfe der Seite. Das
    /// Überlaufmenü sitzt oben in der Navigationsleiste, nicht hier.
    private var actions: some View {
        HStack(spacing: 10) {
            SeriesPlayButton(detail: detail, season: season, provider: provider, play: play)
            SeriesWatchlistButton(slug: detail.slug, title: detail.title, tone: tone)
        }
    }
}

// MARK: - Knöpfe

/// „Jetzt ansehen" beziehungsweise „Weiter ansehen".
///
/// Eigene Ansicht, weil sie den Fortschritt liest: so zeichnet bei einer
/// Änderung nur der Knopf neu und nicht der Kopfbereich mitsamt Artwork.
/// Welche Folge startet, entscheidet `nextPlay` im Kern — dieselbe Regel wie
/// in „Schau weiter" auf der Startseite, damit beide Wege in derselben Folge
/// landen.
struct SeriesPlayButton: View {
    @Environment(LibraryStore.self) private var library
    let detail: SeriesDetail
    let season: String
    let provider: CatalogProvider
    let play: (Episode, Double) -> Void

    var body: some View {
        let target = library.nextPlay(slug: detail.slug, season: season, episodes: detail.episodes, source: provider)
        let resuming = target.resumeAt >= 8

        Button {
            guard let episode = detail.episodes.first(where: { $0.number == target.episode }) else { return }
            play(episode, library.resumeEnabled ? target.resumeAt : 0)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                Text(resuming ? "Weiter ansehen" : "Jetzt ansehen")
                    .font(.system(size: 17, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(NoriTheme.bg)
            .frame(maxWidth: .infinity)
            .frame(height: SeriesMetrics.action)
            .background {
                Capsule().fill(
                    LinearGradient(
                        colors: [Color(red: 0.97, green: 0.985, blue: 1), Color(red: 0.85, green: 0.906, blue: 0.965)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        }
        .buttonStyle(NoriPressStyle(scale: 0.97))
        .disabled(detail.episodes.isEmpty)
        .opacity(detail.episodes.isEmpty ? 0.45 : 1)
        .accessibilityLabel(
            detail.episodes.isEmpty
                ? "Keine Folgen vorhanden"
                : (resuming ? "Folge \(target.episode) fortsetzen" : "Folge \(target.episode) abspielen")
        )
    }
}

/// Der einzige Merklisten-Knopf der Detailseite.
///
/// Oben im Kopfbereich steht ausdrücklich keiner: zwei Knöpfe für dieselbe
/// Sache auf einem Bildschirm sind einer zu viel.
struct SeriesWatchlistButton: View {
    @Environment(LibraryStore.self) private var library
    let slug: String
    let title: String
    let tone: Color?

    @AppStorage(NoriGlassSetting.key) private var glass = true

    var body: some View {
        let marked = library.isFavorite(slug)
        Button {
            library.toggleFavorite(slug, title: title)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: marked ? "heart.fill" : "heart")
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(marked ? "Auf Merkliste" : "Merkliste")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(NoriTheme.fg)
            .frame(maxWidth: .infinity)
            .frame(height: SeriesMetrics.action)
            .noriGlass(
                Capsule(),
                enabled: glass,
                tint: marked ? (tone ?? NoriTheme.accent).opacity(0.35) : nil,
                off: NoriTheme.elevated.opacity(0.92)
            )
            .overlay { Capsule().strokeBorder(.white.opacity(glass ? 0 : 0.16)) }
        }
        .buttonStyle(NoriPressStyle(scale: 0.97))
        .noriHaptic(.selection, trigger: marked)
        .accessibilityLabel(marked ? "Aus der Merkliste entfernen" : "Zur Merkliste hinzufügen")
    }
}

// MARK: - Maße

/// Die Maße, die sich Kopfbereich und Folgenliste teilen.
///
/// Vier Zahlen an einer Stelle statt verstreut: die Knopfhöhe steht auch im
/// Staffelwähler, der Kartenradius auch am Folgenbild.
enum SeriesMetrics {
    /// Höhe der beiden großen Knöpfe und des Staffelwählers. Deutlich über
    /// Apples Mindestmaß — auf der Vorlage sind es die auffälligsten Flächen
    /// der Seite.
    static let action: CGFloat = 56
    /// Größte Breite der Inhaltsspalte — Kopftext und Folgenliste teilen sie
    /// sich, damit beide auf derselben Linie beginnen. Auf dem iPhone nie
    /// erreicht.
    static let content: CGFloat = 760
    /// Größte Breite für Fließtext.
    static let reading: CGFloat = 620
    /// Eckenradius einer Folgenkarte.
    static let card: CGFloat = 20
    /// Eckenradius des Folgenbildes darin.
    static let thumb: CGFloat = 14
    /// Abstand zweier Folgenkarten.
    static let gap: CGFloat = 12
}
