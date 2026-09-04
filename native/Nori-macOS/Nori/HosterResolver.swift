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
        preferredLang: String,
        episodePath: String = ""
    ) async throws -> PlaySource {
        let langMatched = pickLang(hosters, pref: preferredLang)
        let ranked = ordered(langMatched, preferred: preferredHoster)
        guard !ranked.isEmpty else {
            throw NoriError.hoster("Für diese Folge ist kein Hoster eingetragen.")
        }
        // Jeden Fehlschlag mit Hoster und Grund festhalten. Vorher blieb nur die
        // Meldung des zuletzt versuchten Hosters übrig, was nicht erkennen ließ,
        // ob ein einzelner Hoster klemmt oder alle.
        var failures: [String] = []
        for opt in ranked {
            do {
                return try await resolve(opt, episodePath: episodePath)
            } catch {
                var reason = error.localizedDescription
                let prefix = "\(opt.name): "
                if reason.hasPrefix(prefix) { reason.removeFirst(prefix.count) }
                failures.append("\(opt.name) (\(opt.lang)): \(reason)")
            }
        }
        throw NoriError.hoster(
            "Kein Hoster lieferte einen Stream.\n" + failures.joined(separator: "\n")
        )
    }

    static func resolve(_ opt: HosterOption, episodePath: String = "") async throws -> PlaySource {
        let embed = try await followRedirect(opt.redirectPath, episodePath: episodePath)
        return try await extract(embed: embed, hoster: opt.name, lang: opt.lang)
    }

    private static func followRedirect(_ redirectPath: String, episodePath: String = "") async throws -> URL {
        let path = HTML.toAniworldPath(redirectPath)
        let origin: String
        let fullPath: String
        // AniWorld zuerst prüfen: dessen Pfade beginnen mit „/redirect/", was
        // ebenfalls mit „/r" anfängt. Die alte Reihenfolge schickte deshalb
        // jede AniWorld-Weiterleitung an serienstream.to, wo sie mit 404
        // endete — AniWorld war dadurch durchgehend nicht abspielbar.
        // Serienstream verwendet „/r?…", entsprechend genau darauf prüfen.
        if path.hasPrefix("/redirect/") {
            origin = NoriOrigin.aniworld
            fullPath = path
        } else if isSerienstreamRedirect(redirectPath) || isSerienstreamRedirect(path) {
            origin = NoriOrigin.serienstream
            fullPath = isSerienstreamRedirect(redirectPath) ? redirectPath : path
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
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        // Die Weiterleitung wird aus der Episodenseite heraus aufgerufen. Mit
        // dem blanken Origin als Referer weist sich der Aufruf als nicht von
        // dort kommend aus, was manche Quellen abweisen.
        let referer = episodePath.isEmpty ? origin + "/" : origin + normalizeEpisodePath(episodePath)
        req.setValue(referer, forHTTPHeaderField: "Referer")
        defer { session.finishTasksAndInvalidate() }
        let payload = try? await session.data(for: req)

        // 1. Vom Delegate abgefangene Weiterleitung.
        if let landed = tap.externalURL { return landed }

        // 2. Die tatsächlich angesteuerte Adresse. URLSession folgt
        //    Weiterleitungen von sich aus; löst der Delegate dabei nicht aus,
        //    steht das Ziel nur hier. Vorher wurde die Antwort komplett
        //    verworfen, weshalb für jeden Hoster derselbe Fehler ankam.
        if let final = payload?.1.url, isExternalOrigin(final) { return final }

        if let last = tap.lastURL, isExternalOrigin(last) { return last }

        // 3. Manche Quellen liefern statt eines 302 eine HTML-Seite mit
        //    meta-refresh, JS-Sprung oder iframe.
        if let data = payload?.0,
           let html = String(data: data, encoding: .utf8),
           let target = htmlRedirectTarget(html),
           isExternalOrigin(target)
        {
            return target
        }

        throw NoriError.hoster(redirectDiagnosis(payload))
    }

    /// Ohne Zugriff auf die Quelle ist die Fehlermeldung das einzige
    /// Diagnosewerkzeug. Sie soll unterscheiden, ob die Anfrage abgewiesen
    /// wurde, eine Schutzseite kam oder nur die Weiterleitung fehlt.
    private static func redirectDiagnosis(_ payload: (Data, URLResponse)?) -> String {
        let base = "Weiterleitung endete nicht beim Hoster"
        guard let payload else { return "\(base) (keine Antwort)" }

        var parts: [String] = []
        if let http = payload.1 as? HTTPURLResponse {
            parts.append("HTTP \(http.statusCode)")
        }
        if let host = payload.1.url?.host {
            parts.append(host)
        }
        if let html = String(data: payload.0, encoding: .utf8) {
            if looksCaptcha(html) {
                parts.append("Schutzseite/Captcha")
            } else {
                parts.append("\(payload.0.count) Bytes ohne Weiterleitung")
            }
        } else {
            parts.append("\(payload.0.count) Bytes, kein Text")
        }
        return "\(base) (\(parts.joined(separator: ", ")))"
    }

    /// Serienstream-Weiterleitungen sind „/r?…" oder „/r/…" — nicht jeder Pfad,
    /// der mit „/r" beginnt. „/redirect/…" gehört zu AniWorld.
    private static func isSerienstreamRedirect(_ path: String) -> Bool {
        path.hasPrefix("/r?") || path.hasPrefix("/r/") || path == "/r"
    }

    /// Zielt die Adresse auf einen Hoster und nicht zurück auf die Quelle?
    private static func isExternalOrigin(_ url: URL) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        return !url.hostContains("aniworld") && !url.hostContains("serienstream")
    }

    private static func htmlRedirectTarget(_ html: String) -> URL? {
        let patterns = [
            #"<meta[^>]+http-equiv\s*=\s*["']refresh["'][^>]+content\s*=\s*["'][^"']*url\s*=\s*([^"'>\s]+)"#,
            #"window\.location\.(?:href|replace)\s*[=(]\s*["'](https?://[^"']+)["']"#,
            #"location\.href\s*=\s*["'](https?://[^"']+)["']"#,
            #"<iframe[^>]+src\s*=\s*["'](https?://[^"']+)["']"#,
        ]
        for pattern in patterns {
            if let raw = firstGroup(html, pattern), let url = URL(string: raw) { return url }
        }
        return nil
    }

    private static func extract(embed: URL, hoster: String, lang: String) async throws -> PlaySource {
        guard isSafeRemoteURL(embed) else { throw NoriError.hoster("\(hoster): unsichere Ziel-URL") }
        var page = toEmbed(embed, hoster: hoster)
        guard isSafeRemoteURL(page) else { throw NoriError.hoster("\(hoster): unsichere Embed-URL") }
        var html = try await AniworldClient.shared.fetchExternal(page, referer: page.absoluteString)
        if looksCaptcha(html) { throw NoriError.hoster("\(hoster): Captcha") }

        if let bounce = extractBounce(html), bounce != page {
            guard isSafeRemoteURL(bounce) else { throw NoriError.hoster("\(hoster): unsichere Weiterleitung") }
            html = try await AniworldClient.shared.fetchExternal(bounce, referer: page.absoluteString)
            page = bounce
            if looksCaptcha(html) { throw NoriError.hoster("\(hoster): Captcha") }
        }

        let referer = page.absoluteString

        if let voe = extractVoe(html) {
            if let source = voe.source, source.contains(".m3u8"), isAllowed(source) {
                return PlaySource(kind: .hls, url: source, hoster: hoster, lang: lang, referer: referer)
            }
            if let direct = voe.direct, isAllowed(direct) {
                return PlaySource(kind: .mp4, url: direct, hoster: hoster, lang: lang, referer: referer)
            }
            if let source = voe.source, source.contains(".mp4"), isAllowed(source) {
                return PlaySource(kind: .mp4, url: source, hoster: hoster, lang: lang, referer: referer)
            }
        }

        if let media = firstMedia(html) {
            return PlaySource(kind: media.kind, url: media.url, hoster: hoster, lang: lang, referer: referer)
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
        guard let url = URL(string: raw), isSafeRemoteURL(url) else { return false }
        let path = (url.path + (url.query.map { "?\($0)" } ?? "")).lowercased()
        return path.contains(".m3u8") || path.contains(".mp4") || path.contains(".m4s") || path.contains(".ts")
            || path.contains("urlset") || path.contains("/hls") || path.contains("playlist")
    }

    private static func isSafeRemoteURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty
        else { return false }

        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return false }
        if host == "::1" || host == "0.0.0.0" { return false }

        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) {
            let a = octets[0], b = octets[1]
            if a == 10 || a == 127 || a == 0 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(b) { return false }
            if a >= 224 { return false }
        }

        if host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80:") { return false }
        return true
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
        // Beide Quell-Domains ausschließen: bei Serienstream läuft die
        // Weiterleitung über serienstream.to/r?... und macht unterwegs Sprünge
        // innerhalb der eigenen Domain. Ohne die zweite Prüfung wurde so ein
        // Zwischenschritt fälschlich als Hoster-Adresse genommen.
        if let url = request.url, !url.hostContains("aniworld"), !url.hostContains("serienstream") {
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
