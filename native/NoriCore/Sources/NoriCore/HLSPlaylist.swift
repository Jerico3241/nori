import Foundation

/// Eine tatsächlich angebotene Qualitätsstufe eines HLS-Streams.
///
/// „Tatsächlich" ist hier der Punkt: die Stufen werden aus der Master-Playlist
/// gelesen, nicht erfunden. Liefert ein Hoster nur eine Spur — was bei den
/// meisten der Fall ist —, kommt eine leere Liste zurück und die Auswahl
/// erscheint gar nicht erst. Eine Liste mit „1080p / 720p / 480p", die alle
/// dasselbe abspielen, wäre gelogen.
struct HLSVariant: Hashable {
    /// Bits pro Sekunde aus `BANDWIDTH`.
    let bandwidth: Int
    /// Bildhöhe aus `RESOLUTION`, sofern angegeben.
    let height: Int?

    /// „1080p", sonst „5,2 Mbit/s" — irgendetwas Unterscheidbares steht immer
    /// zur Verfügung, denn `BANDWIDTH` ist in HLS Pflicht.
    var label: String {
        if let height { return "\(height)p" }
        let mbit = Double(bandwidth) / 1_000_000
        return String(format: "%.1f Mbit/s", mbit)
    }
}

enum HLSPlaylist {
    /// Die Qualitätsstufen einer Master-Playlist.
    ///
    /// Gibt eine leere Liste zurück, wenn die Adresse keine `.m3u8` ist, der
    /// Abruf scheitert, die Playlist eine reine Medienliste ist oder es nur
    /// eine Stufe gibt. In allen vier Fällen gibt es nichts zu wählen.
    static func variants(of url: URL, referer: String?) async -> [HLSVariant] {
        guard url.absoluteString.contains(".m3u8") else { return [] }

        var request = URLRequest(url: url)
        request.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
            if let refererURL = URL(string: referer),
               let scheme = refererURL.scheme,
               let host = refererURL.host {
                request.setValue("\(scheme)://\(host)", forHTTPHeaderField: "Origin")
            }
        }
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        return parse(text)
    }

    /// Die Zeilen `#EXT-X-STREAM-INF:…` auswerten.
    ///
    /// Getrennt von `variants(of:referer:)`, damit sie ohne Netz prüfbar ist.
    static func parse(_ playlist: String) -> [HLSVariant] {
        var found: [HLSVariant] = []
        for line in playlist.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            let attributes = String(trimmed.dropFirst("#EXT-X-STREAM-INF:".count))
            guard let bandwidth = value(of: "BANDWIDTH", in: attributes).flatMap({ Int($0) }) else { continue }
            let height = value(of: "RESOLUTION", in: attributes)
                .flatMap { $0.split(separator: "x").last }
                .flatMap { Int($0) }
            found.append(HLSVariant(bandwidth: bandwidth, height: height))
        }

        // Nach Höhe entdoppeln: manche Playlists führen dieselbe Auflösung
        // mehrfach, etwa für verschiedene Tonspuren. Von jeder Stufe bleibt
        // die mit der höchsten Bitrate.
        var best: [Int: HLSVariant] = [:]
        for variant in found {
            let key = variant.height ?? -variant.bandwidth
            if let existing = best[key], existing.bandwidth >= variant.bandwidth { continue }
            best[key] = variant
        }
        let unique = best.values.sorted { $0.bandwidth > $1.bandwidth }
        return unique.count > 1 ? unique : []
    }

    /// Ein Attribut aus einer HLS-Attributliste. Werte können in
    /// Anführungszeichen stehen und Kommas enthalten (`CODECS="a,b"`),
    /// deshalb nicht einfach an Kommas trennen.
    private static func value(of key: String, in attributes: String) -> String? {
        guard let range = attributes.range(of: key + "=") else { return nil }
        var rest = attributes[range.upperBound...]
        if rest.first == "\"" {
            rest = rest.dropFirst()
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<end])
        }
        let end = rest.firstIndex(of: ",") ?? rest.endIndex
        return String(rest[..<end])
    }
}
