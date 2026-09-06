import SwiftUI
import AppKit

// MARK: - Farben

/// Nori behält seine dunkle Identität im Dark Mode, folgt aber der
/// Systemeinstellung: im hellen Erscheinungsbild wird eine echte helle
/// Palette benutzt, statt ein dunkles Fenster in eine helle Umgebung zu setzen.
enum NoriTheme {
    static let bg = dynamic(
        light: NSColor(srgbRed: 0.965, green: 0.969, blue: 0.980, alpha: 1),
        dark: NSColor(srgbRed: 0.020, green: 0.024, blue: 0.039, alpha: 1)
    )
    static let surface = dynamic(
        light: NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1),
        dark: NSColor(srgbRed: 0.047, green: 0.055, blue: 0.078, alpha: 1)
    )
    static let elevated = dynamic(
        light: NSColor(srgbRed: 0.902, green: 0.914, blue: 0.937, alpha: 1),
        dark: NSColor(srgbRed: 0.078, green: 0.094, blue: 0.133, alpha: 1)
    )
    static let fg = dynamic(
        light: NSColor(srgbRed: 0.071, green: 0.086, blue: 0.129, alpha: 1),
        dark: NSColor(srgbRed: 0.933, green: 0.945, blue: 0.965, alpha: 1)
    )
    static let muted = dynamic(
        light: NSColor(srgbRed: 0.365, green: 0.400, blue: 0.463, alpha: 1),
        dark: NSColor(srgbRed: 0.545, green: 0.576, blue: 0.655, alpha: 1)
    )
    static let accent = Color.accentColor
    static let border = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    )
    /// Lesbare Schriftfarbe auf accent-gefüllten Flächen. Der Akzent ist ein
    /// kräftiges Orange, auf dem Weiß in beiden Erscheinungsbildern trägt.
    static let onAccent = Color.white
    static let hover = dynamic(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06)
    )

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension Notification.Name {
    /// Wird von „Ablage › Aktualisieren“ (⌘R) gesendet, damit auch Ansichten
    /// mit eigener Datenquelle (Kalender) neu laden.
    static let noriRefreshRequested = Notification.Name("NoriRefreshRequested")

    /// Nach manueller Cover-Auswahl; `object` ist der Slug. Damit aktualisieren
    /// sich auch Kacheln, die gerade in anderen Listen sichtbar sind.
    static let noriCoverChanged = Notification.Name("NoriCoverChanged")
}

// MARK: - Bausteine

struct NoriScreen<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NoriTheme.bg)
            .foregroundStyle(NoriTheme.fg)
    }
}

struct NoriSectionHeader: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let trailing {
                Spacer()
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(NoriTheme.muted)
            }
        }
    }
}

/// Quellenumschalter. Auf dem Mac ein normaler segmentierter Picker statt der
/// per Drag bedienten Kapsel aus der iOS-App – die Geste gibt es hier nicht.
/// Filter für die Bibliothek — kein Moduswechsel mehr.
///
/// Vorher schaltete dieser Regler die ganze App zwischen zwei getrennten
/// Welten um. Jetzt stehen beide Quellen in einer Bibliothek, und der Regler
/// blendet nur aus. „Alle" ist die Vorgabe.
struct ScopePicker: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        @Bindable var library = library
        Picker("Bibliothek", selection: $library.scope) {
            ForEach(LibraryScope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Alles anzeigen oder auf Anime (AniWorld) bzw. Serien (Serienstream) einschränken")
    }
}

struct NoriSeriesLink<Label: View>: View {
    let slug: String
    let titleHint: String
    var provider: CatalogProvider? = nil
    var onOpen: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink {
            SeriesView(slug: slug, titleHint: titleHint, providerOverride: provider)
                .onAppear { onOpen?() }
        } label: {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noriSeriesMenu(slug: slug, title: titleHint)
    }
}

/// Rechtsklick-Menü. Auf dem Mac erwartet man ein Kontextmenü überall dort,
/// wo iOS ein Long-Press-Menü hätte.
private struct SeriesContextMenu: ViewModifier {
    @Environment(LibraryStore.self) private var library
    let slug: String
    let title: String

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(library.isFavorite(slug) ? "Aus Merkliste entfernen" : "Zur Merkliste hinzufügen") {
                library.toggleFavorite(slug, title: title)
            }
        }
    }
}

extension View {
    func noriSeriesMenu(slug: String, title: String) -> some View {
        modifier(SeriesContextMenu(slug: slug, title: title))
    }
}

struct NoriPressStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled && configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Ein Cover, geladen über `CoverImageLoader` statt über `AsyncImage`.
///
/// `AsyncImage` lässt sich keine Kopfzeilen mitgeben. Beide Quellen brauchen
/// aber User-Agent und Referer, sonst antworten sie auf eine Bildanfrage
/// anders als dem Browser. Deshalb dieser kleine Umweg — sichtbar ist er
/// nicht, das Verhalten ist dasselbe: solange kein Bild da ist, steht der
/// Rückfall (in aller Regel der Buchstabe).
struct NoriCoverImage<Fallback: View>: View {
    let url: URL
    let referer: String
    var contentMode: ContentMode = .fill
    @ViewBuilder let fallback: () -> Fallback

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                fallback()
            }
        }
        // Über die Adresse geschlüsselt: ändert sich das Cover einer Kachel
        // (manuelle Auswahl, TMDB-Treffer trifft ein), läuft die Aufgabe neu.
        .task(id: url) {
            image = nil
            guard let data = await CoverImageLoader.shared.data(for: url, referer: referer) else { return }
            guard !Task.isCancelled else { return }
            image = NSImage(data: data)
        }
    }
}

/// Liste oder Raster — die Wahl in Katalog, Kalender und Merkliste.
///
/// Hieß `CatalogLayout` und lag im Katalog, weil es dort zuerst gebraucht
/// wurde. Jetzt teilen sich drei Ansichten den Typ, und ein Name, der nur eine
/// davon nennt, führt in die Irre. `NoriLayout` war nicht zu haben — so heißt
/// auf dem Mac schon das Maß-Enum in `HomeView`.
enum NoriViewMode: String, CaseIterable, Identifiable {
    case list
    case grid

    var id: String { rawValue }
    var symbol: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    var label: String { self == .list ? "Liste" : "Raster" }
}

/// Der Umschalter dafür, für die Fensterleiste.
///
/// Auf dem iPhone sitzt er über dem Inhalt, weil die Navigationsleiste dort
/// schon den Anime/Serien-Schalter trägt. Auf dem Mac ist die Leiste der
/// richtige Ort: dort erwartet man Darstellungsschalter, und der Platz ist da.
struct NoriViewModePicker: View {
    @Binding var raw: String

    var body: some View {
        Picker("Darstellung", selection: $raw) {
            ForEach(NoriViewMode.allCases) { option in
                Label(option.label, systemImage: option.symbol).tag(option.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .help("Zwischen Liste und Raster wechseln")
    }
}

/// Eine Rasterkachel aus den nackten Angaben — Titel, Slug, Quelle.
///
/// `PosterCell` gibt es schon, die hängt aber an `CatalogItem` und bringt das
/// Hover-Infofeld mit. Kalender und Merkliste haben keinen `CatalogItem` und
/// brauchen das Infofeld auch nicht; sie tragen dafür eine eigene Zeile unter
/// dem Titel (Staffel und Folge beziehungsweise nichts).
struct NoriPosterCell: View {
    let title: String
    let slug: String
    var subtitle: String? = nil
    var coverURL: URL? = nil
    var kind: CatalogProvider? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        NoriSeriesLink(slug: slug, titleHint: title, provider: kind, onOpen: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                PosterTile(title: title, slug: slug, coverURL: coverURL, kind: kind)
                Text(title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(NoriTheme.muted)
                        .lineLimit(1)
                }
            }
        }
        .help(title)
    }
}

struct PosterTile: View {
    let title: String
    let slug: String
    var compact: Bool = false
    var coverURL: URL? = nil
    var kind: CatalogProvider? = nil
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remote: URL?
    @State private var hovering = false

    private var radius: CGFloat { compact ? 8 : 12 }
    /// `remote` deckt manuelle Auswahl und Nachschlagen ab und hat deshalb
    /// Vorrang vor dem mitgegebenen Cover der Quelle.
    ///
    /// Zuletzt der aus dem Slug abgeleitete Coverpfad: ein Katalogeintrag
    /// trägt kein Bild, und ohne TMDB-Treffer blieb hier bisher nur der
    /// Buchstabe. Trifft die Ableitung nicht, antwortet die Quelle mit 404 und
    /// es bleibt beim Buchstaben — nicht schlechter als vorher.
    private var shown: URL? { remote ?? coverURL }

    private var source: CatalogProvider { kind ?? library.provider }
    private var lifted: Bool { hovering && !reduceMotion }

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
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(hovering ? NoriTheme.accent.opacity(0.8) : NoriTheme.border, lineWidth: 1)
            }
            .shadow(color: .black.opacity(lifted ? 0.34 : 0.20), radius: lifted ? 14 : 6, y: lifted ? 8 : 3)
            .scaleEffect(lifted ? 1.025 : 1)
            .accessibilityElement()
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(.isImage)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
            .task(id: source.rawValue + "|" + slug + "|" + (coverURL?.absoluteString ?? "")) {
                remote = nil
                // Eine manuelle Auswahl schlägt alles andere.
                if let chosen = await CoverIndex.shared.override(for: slug) {
                    remote = chosen
                    return
                }
                if let coverURL {
                    // Die Detailseite kennt das Cover der Quelle. Merken, damit
                    // Katalog, Kalender und Merkliste es als Rückfallebene haben.
                    await CoverIndex.shared.rememberSource(slug: slug, url: coverURL)
                    return
                }
                if let known = await CoverIndex.shared.url(for: slug) {
                    remote = known
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
            .onReceive(NotificationCenter.default.publisher(for: .noriCoverChanged)) { note in
                guard note.object as? String == slug else { return }
                Task { remote = await CoverIndex.shared.url(for: slug) }
            }
    }

    private var letter: some View {
        ZStack(alignment: .topLeading) {
            NoriTheme.elevated
            Text(String(title.prefix(1)))
                .font(.system(size: compact ? 30 : 44, weight: .semibold, design: .rounded))
                .foregroundStyle(NoriTheme.fg.opacity(0.18))
                .padding(compact ? 6 : 12)
        }
    }
}

enum CoverToneSampler {
    static func sample(url: URL) async -> Color? {
        do {
            var req = URLRequest(url: url)
            req.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let nsImage = NSImage(data: data),
                  let image = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
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

