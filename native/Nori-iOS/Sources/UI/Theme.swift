import SwiftUI
import UIKit

enum NoriTheme {
    static let bg = Color(red: 0.020, green: 0.024, blue: 0.039)
    static let surface = Color(red: 0.047, green: 0.055, blue: 0.078)
    static let elevated = Color(red: 0.078, green: 0.094, blue: 0.133)
    static let fg = Color(red: 0.933, green: 0.945, blue: 0.965)
    static let muted = Color(red: 0.545, green: 0.576, blue: 0.655)
    static let accent = Color(red: 0.843, green: 0.871, blue: 0.918)
    static let border = Color.white.opacity(0.08)

    /// Das Signalblau aus der Katalogvorlage.
    ///
    /// `accent` ist ein sehr helles Grau — richtig für aktive Flächen, die
    /// sich vom dunklen Grund abheben sollen, aber untauglich als **Signal**:
    /// Ein weißer Punkt am Filterknopf ist auf dieser Oberfläche kein
    /// Hinweis, sondern ein Staubkorn. Deshalb ein zweiter Ton, und nur für
    /// die wenigen Stellen, an denen etwas „ist gerade an" sagen muss:
    /// Filterpunkt, aktive Filter-Tags, „Zurücksetzen".
    static let highlight = Color(red: 0.471, green: 0.773, blue: 1.0)
    /// Derselbe Ton als Fläche hinter Text.
    static let highlightSoft = Color(red: 0.471, green: 0.773, blue: 1.0).opacity(0.18)
    /// Die Farbe einer Bewertung. Dieselbe, die die Detailseite für ihren
    /// Stern verwendet.
    static let star = Color(red: 1.0, green: 0.878, blue: 0.478)
}

struct NoriScreen<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NoriTheme.bg.ignoresSafeArea())
            .foregroundStyle(NoriTheme.fg)
    }
}

/// Liste oder Kacheln — die Wahl in Katalog, Kalender und Merkliste.
///
/// Der Wert steht in `@AppStorage`, je Bildschirm unter einem eigenen
/// Schlüssel: im Katalog scrollt man durch Hunderte Titel und will Kacheln,
/// im Kalender zählt die Uhrzeit und damit die Zeile. Ein gemeinsamer Wert
/// würde diese Entscheidung erzwingen.
enum NoriLayout: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list: return "Liste"
        case .grid: return "Kacheln"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }

    /// Rasterspalten der Kachelansicht. `adaptive` statt fester Spaltenzahl:
    /// auf dem iPhone stehen drei Kacheln, auf dem iPad je nach Breite fünf
    /// bis sieben, und beim Drehen ordnet sich das von selbst.
    static let columns = [GridItem(.adaptive(minimum: 104, maximum: 168), spacing: 14, alignment: .top)]
}

/// Der Umschalter dazu.
///
/// Ein Menü statt eines zweiten Segmentschalters: für weitere 148 Punkte ist
/// kein Platz, und das Menü benennt die beiden Ansichten, statt sie nur zu
/// bebildern.
struct LayoutSwitch: View {
    @Binding var layout: NoriLayout

    var body: some View {
        Menu {
            Picker("Ansicht", selection: $layout) {
                ForEach(NoriLayout.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: layout.symbol)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(NoriTheme.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(NoriTheme.elevated, in: Capsule())
            .overlay { Capsule().strokeBorder(NoriTheme.border) }
        }
        .accessibilityLabel("Ansicht")
    }
}

/// Der Umschalter, rechtsbündig über dem Inhalt.
///
/// Er saß in der Navigationsleiste unmittelbar neben dem Anime/Serien-Schalter
/// und drängte sich mit ihm auf einer Höhe. Eine Zeile tiefer, über dem Inhalt,
/// hat er Platz und steht dort, wo er wirkt.
struct LayoutBar: View {
    @Binding var layout: NoriLayout

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            LayoutSwitch(layout: $layout)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

/// Eine Kachel mit Titel und einer Zeile darunter — die Grundform der
/// Kachelansicht in Katalog, Kalender und Merkliste.
///
/// Anders als `CatalogCard` auf der Startseite hat sie keine feste Breite:
/// im Raster bestimmt die Spalte, wie breit sie wird.
struct NoriGridCard: View {
    let title: String
    let slug: String
    var subtitle: String? = nil
    var coverURL: URL? = nil
    var kind: CatalogProvider? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterTile(title: title, slug: slug, coverURL: coverURL, kind: kind)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(NoriTheme.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Überschrift über einem Abschnitt der Kachelansicht — im Raster gibt es
/// keine `Section`-Kopfzeile wie in der Liste.
struct NoriGridHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NoriTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}

struct NoriSeriesLink<Label: View>: View {
    let slug: String
    let titleHint: String
    var scaleOnPress: Bool = false
    var provider: CatalogProvider? = nil
    /// Ob das eingebaute Kontextmenü („Zur Merkliste hinzufügen") mitkommt.
    ///
    /// Die Merkliste schaltet es ab: dort heißt der Eintrag „Aus Merkliste
    /// entfernen" und muss über `removeFavorite` laufen, damit es danach
    /// etwas zurückzunehmen gibt. Zwei `contextMenu` übereinander wären
    /// keine Lösung — sichtbar wäre nur eines, und welches, hängt an der
    /// Reihenfolge der Modifikatoren.
    var showsDefaultMenu: Bool = true
    var onOpen: (() -> Void)? = nil
    @Namespace private var noriZoom
    @NoriReduceMotion private var reduceMotion
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink {
            SeriesView(slug: slug, titleHint: titleHint, providerOverride: provider)
                .onAppear { onOpen?() }
                .modifier(NoriZoomDest(id: slug, namespace: noriZoom, enabled: !reduceMotion))
        } label: {
            label()
                .contentShape(Rectangle())
                // Zeigerrückmeldung auf dem iPad und mit Magic Keyboard: die
                // Kachel hebt sich unter dem Zeiger an. Auf dem iPhone ohne
                // Zeiger passiert nichts — der Modifikator kostet dort nichts.
                .hoverEffect(.lift)
                .modifier(NoriZoomSource(id: slug, namespace: noriZoom, enabled: !reduceMotion))
        }
        .modifier(NoriLinkChrome(scaleOnPress: scaleOnPress))
        .modifier(NoriLinkMenu(slug: slug, title: titleHint, enabled: showsDefaultMenu))
    }
}

/// Merken oder vergessen als Menüeintrag.
///
/// Eigene Ansicht, damit das Kontextmenü nicht die ganze Kachel an den Store
/// bindet: `library.isFavorite` in der Kachel selbst zu lesen ließe jede
/// Kachel bei jeder Änderung der Merkliste neu zeichnen.
private struct NoriFavoriteButton: View {
    @Environment(LibraryStore.self) private var library
    let slug: String
    let title: String

    var body: some View {
        let marked = library.isFavorite(slug)
        Button {
            library.toggleFavorite(slug, title: title)
        } label: {
            Label(
                marked ? "Aus Merkliste entfernen" : "Zur Merkliste hinzufügen",
                systemImage: marked ? "bookmark.slash" : "bookmark"
            )
        }
    }
}

/// Das eingebaute Kontextmenü, abschaltbar.
private struct NoriLinkMenu: ViewModifier {
    let slug: String
    let title: String
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu { NoriFavoriteButton(slug: slug, title: title) }
        } else {
            content
        }
    }
}

private struct NoriLinkChrome: ViewModifier {
    let scaleOnPress: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if scaleOnPress {
            content.buttonStyle(NoriPressStyle(enabled: true))
        } else {
            content.buttonStyle(.plain)
        }
    }
}

private struct NoriZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), enabled {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

private struct NoriZoomDest: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), enabled {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

/// Der Druck auf eine Kachel oder einen Knopf.
///
/// Ein einziger Stil für die ganze App: eine Kachel, die anders drückt als
/// die daneben, fällt auf, ohne dass sich benennen lässt, woran es liegt.
/// Zusätzlich zur Verkleinerung eine Spur Deckkraft — auf einem dunklen
/// Grund ist die Größenänderung allein kaum zu sehen.
struct NoriPressStyle: ButtonStyle {
    var enabled: Bool = true
    /// Wie stark. Große Flächen dürfen weniger schrumpfen als kleine,
    /// sonst wirkt die Bewegung übertrieben.
    var scale: CGFloat = 0.96
    @NoriReduceMotion private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let active = enabled && !reduceMotion && configuration.isPressed
        return configuration.label
            .scaleEffect(active ? scale : 1)
            .opacity(enabled && configuration.isPressed ? 0.86 : 1)
            .animation(NoriMotion.allowed(NoriMotion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// Ein Cover, geladen über `CoverImageLoader` statt über `AsyncImage`.
///
/// `AsyncImage` lässt sich keine Kopfzeilen mitgeben. Beide Quellen brauchen
/// aber User-Agent und Referer, sonst antworten sie auf eine Bildanfrage
/// anders als dem Browser. Deshalb dieser kleine Umweg — sichtbar ist er
/// nicht, das Verhalten ist dasselbe: solange kein Bild da ist, steht der
/// Rückfall (in aller Regel der Buchstabe).
/// Merkt sich, welche Adressen in diesem Programmlauf schon einmal geladen
/// wurden.
///
/// Nur dafür da, das Einblenden **nicht** zu wiederholen: eine Kachel, die
/// beim Zurückscrollen erneut aufblendet, sieht aus, als würde sie neu
/// geladen. Beim ersten Mal ist die Überblendung richtig, danach steht das
/// Bild sofort.
@MainActor
enum NoriImageMemory {
    private static var seen: Set<URL> = []
    /// Ein paar Bildschirme; darüber wird geleert statt gepflegt. Im
    /// schlimmsten Fall blendet ein Cover einmal zu viel auf.
    private static let capacity = 600

    static func isKnown(_ url: URL) -> Bool { seen.contains(url) }

    static func remember(_ url: URL) {
        if seen.count >= capacity { seen.removeAll(keepingCapacity: true) }
        seen.insert(url)
    }
}

/// Ein Cover, geladen über `CoverImageLoader` statt über `AsyncImage`.
///
/// `AsyncImage` lässt sich keine Kopfzeilen mitgeben. Beide Quellen brauchen
/// aber User-Agent und Referer, sonst antworten sie auf eine Bildanfrage
/// anders als dem Browser. Deshalb dieser kleine Umweg — sichtbar ist er
/// nicht, das Verhalten ist dasselbe: solange kein Bild da ist, steht der
/// Rückfall (in aller Regel der Buchstabe).
///
/// Das Bild blendet auf, wenn es geholt werden musste, und steht sofort,
/// wenn es schon einmal da war. Die Größe ändert sich dabei nie: der Rahmen
/// gehört dem Aufrufer, das Bild füllt ihn.
struct NoriCoverImage<Fallback: View>: View {
    let url: URL
    let referer: String
    @ViewBuilder let fallback: () -> Fallback

    @State private var image: UIImage?
    @NoriReduceMotion private var reduceMotion

    var body: some View {
        ZStack {
            fallback()
                .opacity(image == nil ? 1 : 0)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        // Beide Ebenen liegen übereinander und werden ineinander geblendet,
        // statt dass die eine gegen die andere ausgetauscht wird. Ein Tausch
        // zeigt für einen Bildaufbau nichts — den weißen Blitz. Die Kurve
        // setzt die Aufgabe unten von Fall zu Fall, deshalb steht hier kein
        // `animation`-Modifikator.
        .clipped()
        // Über die Adresse geschlüsselt: ändert sich das Cover einer Kachel
        // (TMDB-Treffer trifft ein), läuft die Aufgabe neu.
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

struct PosterTile: View {
    let title: String
    let slug: String
    var compact: Bool = false
    var coverURL: URL? = nil
    var kind: CatalogProvider? = nil
    /// Den Titel in das Bild schreiben statt darunter.
    ///
    /// Für die Zeilen der Startseite: dort bleiben dadurch alle Kacheln
    /// gleich hoch — ein zweizeiliger Titel neben einem einzeiligen verschob
    /// vorher die ganze Reihe — und das Artwork bekommt die volle Fläche.
    /// In den Rasteransichten steht der Titel weiter darunter, wo er sich
    /// besser überfliegen lässt.
    var titleInImage: Bool = false
    /// Abweichender Eckenradius.
    ///
    /// Die Startseite zeichnet ihre Poster etwas runder als die Rasteransichten
    /// — größere Kacheln vertragen einen größeren Radius, und auf der Vorlage
    /// ist er sichtbar weicher. Ein eigener Kacheltyp nur dafür hieße, die
    /// Cover-Auflösung darunter ein zweites Mal zu schreiben.
    var cornerRadius: CGFloat? = nil
    @Environment(LibraryStore.self) private var library
    @NoriReduceMotion private var reduceMotion
    @State private var remote: URL?

    private var radius: CGFloat { cornerRadius ?? (compact ? 10 : 14) }
    /// Zuletzt der aus dem Slug abgeleitete Coverpfad: ein Katalogeintrag
    /// trägt kein Bild, und ohne TMDB-Treffer blieb hier bisher nur der
    /// Buchstabe. Trifft die Ableitung nicht, antwortet die Quelle mit 404 und
    /// es bleibt beim Buchstaben — nicht schlechter als vorher.
    private var shown: URL? { coverURL ?? remote }

    private var source: CatalogProvider { kind ?? library.provider }

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                Group {
                    if let shown {
                        NoriCoverImage(url: shown, referer: source.origin + "/") {
                            letter
                        }
                    } else {
                        letter
                    }
                }
            }
            .overlay {
                if titleInImage {
                    // Kräftiger als ein halbdurchsichtiges Schwarz über der
                    // unteren Hälfte: helle Artworks — weißer Hintergrund,
                    // Schnee, Himmel — verschlucken einen zu zarten Verlauf,
                    // und der Titel steht dann grau auf hell.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: .black.opacity(0.45), location: 0.74),
                            .init(color: .black.opacity(0.9), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .overlay(alignment: .bottomLeading) {
                if titleInImage {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
            .shadow(color: .black.opacity(0.28), radius: compact ? 6 : 10, y: 6)
            .task(id: source.rawValue + "|" + slug + "|" + (coverURL?.absoluteString ?? "")) {
                remote = nil
                if coverURL != nil { return }
                if let cached = await CoverIndex.shared.url(for: slug) {
                    remote = cached
                    return
                }
                remote = await CoverIndex.shared.lookup(slug: slug, title: title, kind: source)
                guard remote == nil else { return }

                // Letzter Ausweg: die Detailseite lesen. Die Adresse des
                // Covers lässt sich nicht aus dem Slug bilden — sie trägt
                // einen Zufallsanteil. Das kostet eine Seite pro Titel, aber
                // nur einmal; danach steht sie in covers.json.
                //
                // Die kurze Pause ist Absicht: beim Durchscrollen wird die
                // Aufgabe vorher abgebrochen, und es geht gar keine Anfrage
                // raus. Geladen wird nur, was auch stehen bleibt.
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                remote = await CoverIndex.shared.fetchSourceCover(slug: slug, provider: source)
            }
    }

    private var letter: some View {
        ZStack(alignment: .topLeading) {
            NoriTheme.elevated
            Text(String(title.prefix(1)))
                .font(.system(size: compact ? 36 : 44, weight: .semibold, design: .rounded))
                .foregroundStyle(NoriTheme.fg.opacity(0.16))
                .padding(compact ? 8 : 12)
        }
    }
}

enum CoverToneSampler {
    static func sample(url: URL) async -> Color? {
        do {
            var req = URLRequest(url: url)
            req.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let image = UIImage(data: data)?.cgImage else { return nil }
            return pick(image)
        } catch {
            return nil
        }
    }

    private static func pick(_ cg: CGImage) -> Color? {
        let w = 24
        let h = 24
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let buf = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var bestScore: Float = -1
        var bestR: CGFloat = 0.84
        var bestG: CGFloat = 0.87
        var bestB: CGFloat = 0.92
        for i in 0 ..< (w * h) {
            let o = i * 4
            let r = CGFloat(buf[o]) / 255
            let g = CGFloat(buf[o + 1]) / 255
            let b = CGFloat(buf[o + 2]) / 255
            let a = CGFloat(buf[o + 3]) / 255
            if a < 0.8 { continue }
            let maxc = max(r, g, b)
            let minc = min(r, g, b)
            let sat = maxc == 0 ? 0 : (maxc - minc) / maxc
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if luma < 0.08 || luma > 0.92 { continue }
            let score = Float(sat) * 1.7 + Float(1 - abs(luma - 0.47)) * 0.4
            if score > bestScore {
                bestScore = score
                bestR = r
                bestG = g
                bestB = b
            }
        }
        if bestScore < 0 { return nil }
        return Color(red: bestR, green: bestG, blue: bestB)
    }
}

