import SwiftUI
import UIKit

// Das Artwork der Detailseite: Bildauswahl, Zuschnitt und der Übergang in den
// Hintergrund.
//
// Eigene Datei, weil hier das einzige Stück echte Bildrechnung der Ansicht
// liegt — alles andere setzt nur Text und Kacheln. Die Hülle darum steht in
// `SeriesHeroView`.

// MARK: - Auswahl

/// Welches Bild den Kopfbereich trägt, und wie es zugeschnitten werden muss.
///
/// Die Reihenfolge ist die der Aufgabenstellung: Breitbild vor Poster vor dem
/// Cover der Quelle. Sie steht hier und nicht in der Ansicht, damit
/// Kopfbereich, Farbabtastung und der Rückfall der Folgenkacheln dasselbe
/// Bild benutzen und nicht drei verschiedene.
struct SeriesArtwork: Equatable {
    var url: URL?
    /// Beide Quellen liefern ihre Cover nur mit passendem Referer aus. TMDB
    /// braucht keinen — dort steht die leere Zeichenkette.
    var referer: String
    /// Hochformat (Poster, Cover) statt Breitbild. Entscheidet über die Höhe
    /// des scharfen Streifens: ein Poster füllt einen hohen Kopfbereich fast
    /// ohne Verlust, ein Breitbild verlöre darin die Hälfte seiner Breite.
    var portrait: Bool

    static let none = SeriesArtwork(url: nil, referer: "", portrait: false)

    static func resolve(
        details: CoverDetails,
        sourceCover: URL?,
        provider: CatalogProvider
    ) -> SeriesArtwork {
        if let backdrop = details.backdrop {
            return SeriesArtwork(url: backdrop, referer: "", portrait: false)
        }
        if let poster = details.poster {
            return SeriesArtwork(url: poster, referer: "", portrait: true)
        }
        if let cover = sourceCover {
            return SeriesArtwork(url: cover, referer: provider.origin + "/", portrait: true)
        }
        return .none
    }

    /// Die Höhe des scharfen Streifens.
    ///
    /// Ein Breitbild in einem hohen Rahmen formatfüllend zu zeigen heißt,
    /// seitlich abzuschneiden — bei einem 16:9-Bild in einem quadratischen
    /// Rahmen bleibt gut die Hälfte übrig, und die Hauptfigur steht selten
    /// genau in der Mitte. Der Streifen bleibt deshalb flach genug, dass vom
    /// Breitbild das meiste stehen bleibt; darunter übernimmt die unscharfe
    /// Fassung. Ein Poster ist ohnehin hochformatig und darf höher stehen.
    ///
    /// Der Deckel an der Höhe ist für iPad und Querformat: nach der Breite
    /// allein gerechnet stünde dort ein Kopfbild, das höher ist als der
    /// Bildschirm, und die Seite begänne unterhalb des Sichtbaren.
    func bandHeight(in size: CGSize) -> CGFloat {
        min(size.width * (portrait ? 1.12 : 0.78), size.height * 0.45)
    }

    /// Wo im Bild der Zuschnitt sitzt, wenn es höher ist als sein Rahmen.
    ///
    /// Oberhalb der Mitte: auf Postern und Covern stehen Gesicht und
    /// Schriftzug im oberen Drittel, ein mittiger Zuschnitt köpft sie.
    var verticalAnchor: CGFloat { portrait ? 0.24 : 0.42 }
}

// MARK: - Akzentfarbe

extension Color {
    /// Die abgetastete Coverfarbe, so weit aufgehellt, dass sie auf Noris
    /// dunklem Grund trägt.
    ///
    /// `CoverToneSampler` sucht die auffälligste Farbe des Artworks, nicht die
    /// hellste — bei einem düsteren Cover kommt ein tiefes Braun oder
    /// Flaschengrün zurück. Als Fortschrittsring auf Fastschwarz ist das
    /// unsichtbar. Der Farbton bleibt, Helligkeit und Sättigung werden in
    /// einen brauchbaren Bereich gezogen.
    func noriReadableAccent() -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return Color(
            hue: Double(hue),
            saturation: Double(min(max(saturation, 0.35), 0.82)),
            brightness: Double(max(brightness, 0.74))
        )
    }
}

// MARK: - Bild mit Zuschnittpunkt

/// Ein Bild, das seinen Rahmen füllt — mit wählbarem Zuschnittpunkt.
///
/// `NoriCoverImage` reicht dafür nicht: `scaledToFill` schneidet immer mittig,
/// und genau das ist auf einem hohen Kopfbereich die falsche Stelle. Hier wird
/// der Maßstab selbst gerechnet und das Bild verschoben, bevor der Rahmen es
/// beschneidet.
///
/// Geladen wird über `CoverImageLoader` — derselbe Zwischenspeicher wie bei den
/// Kacheln, und nur der kann die Kopfzeilen mitgeben, die beide Quellen für
/// Bildanfragen verlangen.
struct NoriAnchoredImage<Fallback: View>: View {
    let url: URL
    let referer: String
    /// 0 = oben bündig, 1 = unten bündig. Wirkt nur in der Richtung, in der
    /// das Bild übersteht.
    var verticalAnchor: CGFloat = 0.4
    var horizontalAnchor: CGFloat = 0.5
    @ViewBuilder let fallback: () -> Fallback

    @State private var image: UIImage?
    @NoriReduceMotion private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                fallback().opacity(image == nil ? 1 : 0)
                if let image, image.size.width > 0, image.size.height > 0 {
                    let scale = max(geo.size.width / image.size.width, geo.size.height / image.size.height)
                    let shown = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(
                            x: (geo.size.width - shown.width) * horizontalAnchor,
                            y: (geo.size.height - shown.height) * verticalAnchor
                        )
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
        .task(id: url) {
            image = nil
            let known = NoriImageMemory.isKnown(url)
            guard let data = await CoverImageLoader.shared.data(for: url, referer: referer) else { return }
            guard !Task.isCancelled, let decoded = UIImage(data: data) else { return }
            NoriImageMemory.remember(url)
            if !known, !reduceMotion {
                withAnimation(NoriMotion.micro) { image = decoded }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { image = decoded }
            }
        }
    }
}

// MARK: - Kopfbild

/// Das Artwork hinter dem Kopfbereich, in vier Lagen.
///
/// 1. Die Grundfarbe, damit unter einem Bild mit Alphakanal nichts schwarz
///    durchscheint.
/// 2. Dieselbe Aufnahme unscharf über die volle Höhe. Sie füllt, was der
///    scharfe Streifen freilässt, und liefert die Umgebungsfarbe.
/// 3. Der scharfe Streifen oben, nach unten ausgeblendet — dadurch gibt es
///    keine Kante zwischen scharf und unscharf.
/// 4. Der Verlauf in Noris Hintergrundfarbe, dazu ein schwacher Schimmer in
///    der vorherrschenden Farbe des Artworks.
///
/// Die Ansicht bringt keine eigene Größe mit; sie wird als `.background`
/// hinter den Kopfbereich gelegt und nimmt dessen Maße an.
struct SeriesBackdrop: View {
    let artwork: SeriesArtwork
    let tone: Color?
    let screen: CGSize

    var body: some View {
        ZStack(alignment: .top) {
            NoriTheme.bg

            if let url = artwork.url {
                NoriAnchoredImage(url: url, referer: artwork.referer, verticalAnchor: 0.3) {
                    NoriTheme.elevated
                }
                .blur(radius: 52, opaque: true)
                .saturation(0.9)
                .brightness(-0.22)
                .opacity(0.82)

                NoriAnchoredImage(
                    url: url,
                    referer: artwork.referer,
                    verticalAnchor: artwork.verticalAnchor
                ) {
                    NoriTheme.elevated
                }
                .frame(height: artwork.bandHeight(in: screen))
                .mask(bandFade)
            }

            fade
            glow
        }
        .allowsHitTesting(false)
    }

    /// Der scharfe Streifen verliert sich nach unten in der unscharfen Lage,
    /// statt an einer Linie aufzuhören.
    ///
    /// Der Übergang beginnt früh und endet hart. Viele Cover tragen den Titel
    /// eingebrannt; hält der scharfe Streifen unten zu lange durch, steht der
    /// Schriftzug ein zweites Mal blass unter dem echten.
    private var bandFade: some View {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.42),
                .init(color: .white.opacity(0.20), location: 0.70),
                .init(color: .clear, location: 0.88)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Vom Bild in den Seitenhintergrund. Die letzte Stufe ist deckend: der
    /// Inhalt darunter beginnt ohne sichtbare Naht.
    private var fade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: NoriTheme.bg.opacity(0.12), location: 0.30),
                .init(color: NoriTheme.bg.opacity(0.58), location: 0.64),
                .init(color: NoriTheme.bg.opacity(0.93), location: 0.87),
                .init(color: NoriTheme.bg, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Der Schimmer aus der Coverfarbe. Bewusst schwach und nur oben rechts:
    /// die Seite soll dunkel bleiben und nicht eingefärbt wirken.
    @ViewBuilder
    private var glow: some View {
        if let tone {
            RadialGradient(
                colors: [tone.opacity(0.20), .clear],
                center: UnitPoint(x: 0.74, y: 0.14),
                startRadius: 0,
                endRadius: screen.width * 0.95
            )
            .blendMode(.plusLighter)
        }
    }
}
