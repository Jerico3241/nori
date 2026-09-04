import SwiftUI
import AppKit

enum NoriTheme {
    static let bg = Color(red: 0.020, green: 0.024, blue: 0.039)
    static let surface = Color(red: 0.047, green: 0.055, blue: 0.078)
    static let elevated = Color(red: 0.078, green: 0.094, blue: 0.133)
    static let fg = Color(red: 0.933, green: 0.945, blue: 0.965)
    static let muted = Color(red: 0.545, green: 0.576, blue: 0.655)
    static let accent = Color(red: 0.843, green: 0.871, blue: 0.918)
    static let border = Color.white.opacity(0.08)
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

struct NoriSeriesLink<Label: View>: View {
    let slug: String
    let titleHint: String
    var scaleOnPress: Bool = false
    var provider: CatalogProvider? = nil
    var onOpen: (() -> Void)? = nil
    @Namespace private var noriZoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink {
            SeriesView(slug: slug, titleHint: titleHint, providerOverride: provider)
                .onAppear { onOpen?() }
                .modifier(NoriZoomDest(id: slug, namespace: noriZoom, enabled: !reduceMotion))
        } label: {
            label()
                .contentShape(Rectangle())
                .modifier(NoriZoomSource(id: slug, namespace: noriZoom, enabled: !reduceMotion))
        }
        .modifier(NoriLinkChrome(scaleOnPress: scaleOnPress && !reduceMotion))
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
        if #available(macOS 15.0, *), enabled {
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
        if #available(macOS 15.0, *), enabled {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}

struct NoriPressStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(enabled && configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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

    private var radius: CGFloat { compact ? 10 : 14 }
    private var shown: URL? { coverURL ?? remote }

    var body: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay {
                Group {
                    if let shown {
                        AsyncImage(url: shown) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                letter
                            }
                        }
                    } else {
                        letter
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NoriTheme.border)
            }
            .shadow(color: .black.opacity(0.28), radius: compact ? 6 : 10, y: 6)
            .task(id: slug) {
                if coverURL != nil { return }
                if let cached = await CoverIndex.shared.url(for: slug) {
                    remote = cached
                    return
                }
                remote = await CoverIndex.shared.lookup(slug: slug, title: title, kind: kind ?? library.provider)
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
