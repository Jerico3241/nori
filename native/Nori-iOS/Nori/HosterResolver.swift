import Foundation

enum HosterResolver {
    private static let voeTokens = ["@$", "^^", "~@", "%?", "*~", "!!", "#&"]

    static func rank(_ name: String) -> Int {
        let n = name.lowercased().filter(\.isLetter)
        if n.contains("voe") { return 0 }
        if n.contains("vidmoly") { return 1 }
        if n.contains("vidoza") { return 2 }
        if n.contains("lulu") { return 3 }
        if n.contains("speedfiles") { return 4 }
        if n.contains("filemoon") { return 5 }
        if n.contains("dood") { return 9 }
        return 7
    }

    static func ordered(_ hosters: [HosterOption], preferred: String?) -> [HosterOption] {
        let want = preferred?.lowercased() ?? ""
        return hosters.sorted {
            let a = (!want.isEmpty && $0.name.lowercased() == want) ? -1 : rank($0.name)
            let b = (!want.isEmpty && $1.name.lowercased() == want) ? -1 : rank($1.name)
            return a < b
        }
    }

    static func pickLang(_ hosters: [HosterOption], pref: String) -> [HosterOption] {
        let order = [pref, "DE", "GerSub", "EN"]
        for lang in order {
            let hit = hosters.filter { $0.lang.caseInsensitiveCompare(lang) == .orderedSame }
            if !hit.isEmpty { return hit }
        }
        return hosters
    }

    static func resolveBest(
        hosters: [HosterOption],
        preferredHoster: String,
        preferredLang: String
    ) async throws -> PlaySource {
        let langMatched = pickLang(hosters, pref: preferredLang)
        let ranked = ordered(langMatched, preferred: preferredHoster)
        var last = "Kein spielbarer Hoster"
        for opt in ranked {
            do {
                return try await resolve(opt)
            } catch {
                last = error.localizedDescription
            }
        }
        throw NoriError.hoster(last)
    }

    static func resolve(_ opt: HosterOption) async throws -> PlaySource {
        let embed = try await followRedirect(opt.redirectPath)
        return try await extract(embed: embed, hoster: opt.name, lang: opt.lang)
    }

    private static func followRedirect(_ redirectPath: String) async throws -> URL {
        let path = HTML.toAniworldPath(redirectPath)
        let origin: String
        let fullPath: String
        // /r?t=… / /r/  = Serienstream. Nicht /redirect/ (AniWorld) — hasPrefix("/r") wäre true für beides.
        if Self.isSerienstreamPlayPath(redirectPath) || Self.isSerienstreamPlayPath(path) {
            origin = NoriOrigin.serienstream
            fullPath = Self.isSerienstreamPlayPath(redirectPath) ? redirectPath : path
        } else if path.hasPrefix("/redirect/") {
            origin = NoriOrigin.aniworld
            fullPath = path
        } else {
            throw NoriError.hoster("Ungültiger Hoster")
        }
        guard let url = URL(string: origin + fullPath) else { throw NoriError.hoster("Ungültige URL") }

        let tap = RedirectTap()
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = HTTPCookieStorage.shared
        let session = URLSession(configuration: config, delegate: tap, delegateQueue: nil)
        var req = URLRequest(url: url)
        req.setValue(NoriOrigin.ua, forHTTPHeaderField: "User-Agent")
        req.setValue("de-DE,de;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(origin + "/", forHTTPHeaderField: "Referer")
        _ = try? await session.data(for: req)
        if let landed = tap.externalURL { return landed }
        if let last = tap.lastURL, !last.hostContains("aniworld"), !last.hostContains("serienstream") { return last }
        throw NoriError.hoster("Hoster-URL nicht lesbar")
    }

    private static func extract(embed: URL, hoster: String, lang: String) async throws -> PlaySource {
        var page = toEmbed(embed, hoster: hoster)
        var html = try await AniworldClient.shared.fetchExternal(page, referer: page.absoluteString)
        if looksCaptcha(html) { throw NoriError.hoster("\(hoster): Captcha") }

        if let bounce = extractBounce(html), bounce != page {
            html = try await AniworldClient.shared.fetchExternal(bounce, referer: page.absoluteString)
            page = bounce
            if looksCaptcha(html) { throw NoriError.hoster("\(hoster): Captcha") }
        }

        if let voe = extractVoe(html) {
            if let source = voe.source, source.contains(".m3u8"), isAllowed(source) {
                return PlaySource(kind: .hls, url: source, hoster: hoster, lang: lang)
            }
            if let direct = voe.direct, isAllowed(direct) {
                return PlaySource(kind: .mp4, url: direct, hoster: hoster, lang: lang)
            }
            if let source = voe.source, source.contains(".mp4"), isAllowed(source) {
                return PlaySource(kind: .mp4, url: source, hoster: hoster, lang: lang)
            }
        }

        if let media = firstMedia(html) {
            return PlaySource(kind: media.kind, url: media.url, hoster: hoster, lang: lang)
        }
        throw NoriError.hoster("\(hoster) liefert keinen Stream")
    }

    private static func toEmbed(_ url: URL, hoster: String) -> URL {
        let n = hoster.lowercased()
        guard n.contains("filemoon") || n.contains("vidmoly") || n.contains("dood") else { return url }
        let raw = url.absoluteString.replacingOccurrences(of: "/d/", with: "/e/").replacingOccurrences(of: "/v/", with: "/e/")
        return URL(string: raw) ?? url
    }

    private static func extractBounce(_ html: String) -> URL? {
        let patterns = [
            #"window\.location\.href\s*=\s*['"](https?://[^'"]+/e/[A-Za-z0-9]+)['"]"#,
            #"location\.href\s*=\s*['"](https?://[^'"]+/e/[A-Za-z0-9]+)['"]"#,
            #"window\.location\.href\s*=\s*['"](https?://[^'"]+)['"]"#,
        ]
        for p in patterns {
            if let match = html.range(of: p, options: .regularExpression) {
                let chunk = String(html[match])
                if let inner = chunk.range(of: #"https?://[^'"]+"#, options: .regularExpression) {
                    let s = String(chunk[inner])
                    if s.contains("translate") || s.contains("voe.sx/api") { continue }
                    return URL(string: s)
                }
            }
        }
        return nil
    }

    private static func extractVoe(_ html: String) -> (source: String?, direct: String?)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            guard m.numberOfRanges > 1 else { continue }
            let blob = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = blob.data(using: .utf8),
                  let parsed = try? JSONSerialization.jsonObject(with: data)
            else { continue }
            let encrypted: String?
            if let arr = parsed as? [Any], let first = arr.first as? String {
                encrypted = first
            } else {
                encrypted = nil
            }
            guard let encrypted, let cfg = decodeVoe(encrypted) else { continue }
            let source = cfg["source"] as? String
            let direct = cfg["direct_access_url"] as? String
            if source != nil || direct != nil { return (source, direct) }
        }
        return nil
    }

    private static func decodeVoe(_ encrypted: String) -> [String: Any]? {
        var s = rot13(encrypted)
        for token in voeTokens { s = s.replacingOccurrences(of: token, with: "_") }
        s = s.replacingOccurrences(of: "_", with: "")
        guard let step1 = Data(base64Encoded: padBase64(s)) else { return nil }
        let shifted = String(bytes: step1.map { $0 &- 3 }, encoding: .isoLatin1) ?? ""
        let reversed = String(shifted.reversed())
        guard let jsonData = Data(base64Encoded: padBase64(reversed)),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func rot13(_ input: String) -> String {
        String(input.map { ch in
            guard let ascii = ch.asciiValue, let scalar = UnicodeScalar(Int(ascii)) else { return ch }
            if (65...90).contains(ascii) { return Character(UnicodeScalar((Int(ascii) - 65 + 13) % 26 + 65)!) }
            if (97...122).contains(ascii) { return Character(UnicodeScalar((Int(ascii) - 97 + 13) % 26 + 97)!) }
            return Character(scalar)
        })
    }

    private static func padBase64(_ s: String) -> String {
        let pad = (4 - (s.count % 4)) % 4
        return s + String(repeating: "=", count: pad)
    }

    private static func firstMedia(_ html: String) -> (kind: PlayKind, url: String)? {
        let hlsPatterns = [
            #"file\s*[:=]\s*["'](https:[^"']+\.m3u8[^"']*)["']"#,
            #"src\s*[:=]\s*["'](https:[^"']+\.m3u8[^"']*)["']"#,
            #"["'](https:[^"']+\.m3u8[^"']*)["']"#,
        ]
        for p in hlsPatterns {
            if let url = firstGroup(html, p), isAllowed(url) { return (.hls, url) }
        }
        let mp4Patterns = [
            #"file\s*[:=]\s*["'](https:[^"']+\.mp4[^"']*)["']"#,
            #"["'](https:[^"']+\.mp4[^"']*)["']"#,
        ]
        for p in mp4Patterns {
            if let url = firstGroup(html, p), isAllowed(url), !url.contains("test-videos.co.uk") {
                return (.mp4, url)
            }
        }
        return nil
    }

    private static func firstGroup(_ html: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let m = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func isAllowed(_ raw: String) -> Bool {
        guard let url = URL(string: raw), let host = url.host, url.scheme == "https" else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasPrefix("127.") { return false }
        let path = (url.path + (url.query.map { "?\($0)" } ?? "")).lowercased()
        return path.contains(".m3u8") || path.contains(".mp4") || path.contains(".m4s") || path.contains(".ts")
            || path.contains("urlset") || path.contains("/hls") || path.contains("playlist")
    }

    private static func looksCaptcha(_ html: String) -> Bool {
        let h = html.prefix(4000).lowercased()
        return h.contains("cf-turnstile") || h.contains("g-recaptcha") || h.contains("hcaptcha")
            || h.contains("just a moment") || h.contains("ddos-guard")
    }
}

private final class RedirectTap: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var lastURL: URL?
    var externalURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        lastURL = request.url
        if let url = request.url, !url.hostContains("aniworld") {
            externalURL = url
            return nil
        }
        return request
    }
}

private extension URL {
    func hostContains(_ needle: String) -> Bool {
        (host ?? "").localizedCaseInsensitiveContains(needle)
    }
}
