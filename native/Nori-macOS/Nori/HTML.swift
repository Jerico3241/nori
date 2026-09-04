import Foundation
import SwiftSoup

enum HTML {
    static func toAniworldPath(_ href: String) -> String {
        let cleaned = href.replacingOccurrences(of: "&", with: "&").trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: #"/anime/stream/[^?\s#]+"#, options: .regularExpression) {
            return String(cleaned[range]).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        }
        if let range = cleaned.range(of: #"/serie/[^?\s#]+"#, options: .regularExpression) {
            return String(cleaned[range]).replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        }
        if let range = cleaned.range(of: #"/redirect/\d+"#, options: .regularExpression) {
            return String(cleaned[range])
        }
        if cleaned.hasPrefix("/r") {
            return cleaned.split(separator: "#").first.map(String.init) ?? cleaned
        }
        if cleaned.hasPrefix("/") {
            return cleaned.split(separator: "?").first.map(String.init) ?? cleaned
        }
        return ""
    }

    static func unique(_ list: [String]) -> [String] {
        var out: [String] = []
        for item in list {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !out.contains(t) { out.append(t) }
        }
        return out
    }

    static func flagLabel(_ title: String) -> String? {
        let t = title.lowercased()
        if t.contains("untertitel") || t.contains("gersub") || t.contains("japanese-german") { return "GerSub" }
        if t.contains("english") || t.contains("englisch") { return "EN" }
        if t.contains("deutsch") || t.contains("german") { return "DE" }
        if t.contains("japan") { return "JP" }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseCatalog(_ html: String) throws -> [CatalogItem] {
        let doc = try SwiftSoup.parse(html)
        var seen: [String: CatalogItem] = [:]
        var items: [CatalogItem] = []

        func ingest(href: String, title: String, altRaw: String, genre: String?) {
            let path = toAniworldPath(href)
            guard let match = path.range(of: #"^/anime/stream/([^/?#]+)"#, options: .regularExpression) else { return }
            let slugPart = String(path[match])
            let slug = slugPart.split(separator: "/").last.map(String.init) ?? ""
            guard !slug.isEmpty else { return }
            let cleanTitle = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { return }
            let alts = unique(
                altRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.lowercased() != cleanTitle.lowercased() }
            ).prefix(8).map { $0 }

            if var existing = seen[slug] {
                if let genre, !existing.genres.contains(genre) {
                    existing.genres.append(genre)
                    seen[slug] = existing
                    if let idx = items.firstIndex(where: { $0.slug == slug }) { items[idx] = existing }
                }
                return
            }
            let rec = CatalogItem(slug: slug, title: cleanTitle, alts: alts, genres: genre.map { [$0] } ?? [])
            seen[slug] = rec
            items.append(rec)
        }

        let genreBlocks = try doc.select(".genre")
        if genreBlocks.size() > 0 {
            for block in genreBlocks.array() {
                let genre = try block.select("h3").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
                for a in try block.select("a").array() {
                    ingest(
                        href: try a.attr("href"),
                        title: try a.text(),
                        altRaw: try a.attr("data-alternative-title"),
                        genre: (genre?.isEmpty == false) ? genre : nil
                    )
                }
            }
        }

        if items.count < 20 {
            for a in try doc.select("a").array() {
                ingest(
                    href: try a.attr("href"),
                    title: try a.text(),
                    altRaw: (try? a.attr("data-alternative-title")) ?? (try? a.attr("data-alternativeTitles")) ?? "",
                    genre: nil
                )
            }
        }
        return items
    }

    static func parseSeries(_ html: String, slug: String, requestedSeason: String?) throws -> SeriesDetail {
        let doc = try SwiftSoup.parse(html)
        let titleEl = try doc.select(".series-title h1").first()
        let spanTitle = try titleEl?.select("span").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let elementTitle = try titleEl?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = try doc.select("h1").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let title = spanTitle?.nilIfEmpty ?? elementTitle?.nilIfEmpty ?? fallbackTitle?.nilIfEmpty ?? slug

        let altRaw = (try? titleEl?.attr("data-alternativeTitles")) ?? (try? titleEl?.attr("title")) ?? ""
        let alts = unique(
            altRaw.replacingOccurrences(of: #"^Animes Stream:\s*"#, with: "", options: .regularExpression)
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != title.lowercased() }
        ).prefix(8).map { $0 }

        let desEl = try doc.select("p.seri_des").first()
        let fullDescription = (try? desEl?.attr("data-full-description")) ?? ""
        let shortDescription = try desEl?.text()
            .replacingOccurrences(of: "mehr anzeigen", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = fullDescription.nilIfEmpty ?? shortDescription

        let img = try doc.select(".seriesCoverBox img").first()
        let coverSrc = (try? img?.attr("data-src")).flatMap { $0.isEmpty ? nil : $0 } ?? (try? img?.attr("src"))
        var coverPath: String?
        if let coverSrc, coverSrc.hasPrefix("/public/"), !coverSrc.hasPrefix("data:") {
            coverPath = coverSrc
        } else if let coverSrc, coverSrc.contains("/public/img/cover/") {
            coverPath = coverSrc.replacingOccurrences(of: #"^https?://[^/]+"#, with: "", options: .regularExpression)
        }

        let yearStart = try doc.select("span[itemprop=startDate]").text().nilIfEmpty
        let yearEnd = try doc.select("span[itemprop=endDate]").text().nilIfEmpty
        let fsk = try doc.select("[data-fsk]").attr("data-fsk").nilIfEmpty
        let imdb = try doc.select("a.imdb-link").attr("data-imdb").nilIfEmpty
        let genres = unique(
            try doc.select("a.genreButton").array().map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter {
                    let n = $0.lowercased()
                    return !n.isEmpty && n != "ger" && n != "engsub" && n != "gersub"
                }
        )

        let seasons = try parseSeasons(doc)
        let episodes = try parseEpisodes(doc)

        var activeSeason = requestedSeason ?? ""
        if activeSeason.isEmpty {
            let activeHref = toAniworldPath(try doc.select(".hosterSiteDirectNav a.active").attr("href"))
            if activeHref.contains("/filme") {
                activeSeason = "filme"
            } else if let m = activeHref.range(of: #"staffel-(\d+)"#, options: .regularExpression) {
                let chunk = String(activeHref[m])
                activeSeason = chunk.split(separator: "-").last.map(String.init) ?? "1"
            } else {
                activeSeason = seasons.first(where: { $0.id != "filme" })?.id ?? seasons.first?.id ?? "1"
            }
        }

        return SeriesDetail(
            slug: slug,
            title: title,
            alts: alts,
            description: description,
            coverPath: coverPath,
            yearStart: yearStart,
            yearEnd: yearEnd,
            fsk: fsk,
            imdb: imdb,
            genres: genres,
            seasons: seasons,
            activeSeason: activeSeason,
            episodes: episodes
        )
    }

    static func parseSeasons(_ doc: Document) throws -> [SeasonRef] {
        var seasons: [SeasonRef] = []
        var seen = Set<String>()
        let firstList = try doc.select(".hosterSiteDirectNav").first()?.select("ul").first()
        for a in try firstList?.select("a").array() ?? [] {
            let href = toAniworldPath(try a.attr("href"))
            if href.contains("/filme") {
                if !seen.contains("filme") {
                    seen.insert("filme")
                    seasons.append(SeasonRef(id: "filme", label: "Filme"))
                }
                continue
            }
            if let m = href.range(of: #"staffel-(\d+)"#, options: .regularExpression) {
                let id = String(href[m]).split(separator: "-").last.map(String.init) ?? ""
                if !id.isEmpty, !seen.contains(id) {
                    seen.insert(id)
                    seasons.append(SeasonRef(id: id, label: "Staffel \(id)"))
                }
            }
        }
        seasons.sort {
            if $0.id == "filme" { return false }
            if $1.id == "filme" { return true }
            return (Int($0.id) ?? 0) < (Int($1.id) ?? 0)
        }
        if seasons.isEmpty { seasons.append(SeasonRef(id: "1", label: "Staffel 1")) }
        return seasons
    }

    static func parseEpisodes(_ doc: Document) throws -> [Episode] {
        var episodes: [Episode] = []
        for tr in try doc.select("table.seasonEpisodesList tbody tr").array() {
            let titleLink = try tr.select(".seasonEpisodeTitle a").first()
            var href = toAniworldPath((try? titleLink?.attr("href")) ?? "")
            if href.isEmpty {
                href = toAniworldPath(try tr.select("a[href*=episode-]").attr("href"))
            }
            if href.isEmpty {
                href = toAniworldPath(try tr.select("a[href*=/filme/film-]").attr("href"))
            }

            let film = href.range(of: #"/filme/film-(\d+)"#, options: .regularExpression)
            let episodeMatch = href.range(of: #"episode-(\d+)"#, options: .regularExpression)
            let metaNumber = (try? tr.select("meta[itemprop=episodeNumber]").attr("content")) ?? ""
            let cellNumber = (try? tr.select("td").first()?.text()) ?? ""
            var numRaw = ""
            if let film {
                numRaw = String(href[film]).split(separator: "-").last.map(String.init) ?? ""
            } else if let episodeMatch {
                numRaw = String(href[episodeMatch]).split(separator: "-").last.map(String.init) ?? ""
            } else if !metaNumber.isEmpty {
                numRaw = metaNumber
            } else {
                numRaw = cellNumber
            }
            let digits = numRaw.filter { $0.isNumber }
            let number = Int(digits) ?? (episodes.count + 1)

            let germanTitle = try titleLink?.select("strong").text()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let englishTitle = try titleLink?.select("span").text()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hosters = unique(
                try tr.select("i.icon").array().compactMap { el -> String? in
                    let t = (try? el.attr("title")) ?? ""
                    let name = t.replacingOccurrences(of: #"^Hoster\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty ? nil : name
                }
            )
            let languages = unique(
                try tr.select("img.flag").array().compactMap { el -> String? in
                    flagLabel((try? el.attr("title")) ?? (try? el.attr("alt")) ?? "")
                }
            )
            if href.isEmpty, germanTitle.isEmpty, englishTitle.isEmpty { continue }
            let fallback = film != nil ? "Film \(number)" : "Folge \(number)"
            episodes.append(
                Episode(
                    number: number,
                    germanTitle: germanTitle.isEmpty ? (englishTitle.isEmpty ? fallback : englishTitle) : germanTitle,
                    englishTitle: englishTitle,
                    path: href,
                    hosters: hosters,
                    languages: languages
                )
            )
        }
        return episodes
    }

    static func parseWatch(_ html: String, path: String) throws -> WatchInfo {
        let doc = try SwiftSoup.parse(html)
        let h1 = try doc.select("h1").first()?.text().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let strongTitle = try doc.select(".seasonEpisodeTitle strong").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let h2Title = try doc.select("h2").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        let germanTitle = strongTitle?.nilIfEmpty ?? h2Title?.nilIfEmpty ?? h1
        let englishTitle = try doc.select(".seasonEpisodeTitle span").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var hosters: [HosterOption] = []
        var seen = Set<String>()

        func push(redirectPath: String, langKey: String, name: String) {
            var pathOnly = toAniworldPath(redirectPath)
            if pathOnly.isEmpty { pathOnly = redirectPath }
            guard pathOnly.hasPrefix("/redirect/") || pathOnly.hasPrefix("/r") else { return }
            let key = "\(pathOnly)|\(langKey)"
            if seen.contains(key) { return }
            seen.insert(key)
            let clean = name.replacingOccurrences(of: #"^Hoster\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            hosters.append(
                HosterOption(
                    name: clean.isEmpty ? "Hoster" : clean,
                    lang: langLabel(langKey),
                    langKey: langKey,
                    redirectPath: pathOnly
                )
            )
        }

        for el in try doc.select("li[data-link-id]").array() {
            let id = (try? el.attr("data-link-id")) ?? ""
            let target = (try? el.attr("data-link-target")).flatMap { $0.isEmpty ? nil : $0 } ?? (id.isEmpty ? "" : "/redirect/\(id)")
            let langKey = (try? el.attr("data-lang-key")).flatMap { $0.isEmpty ? nil : $0 } ?? "1"
            let name =
                (try? el.select("h4").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? (try? el.select("i.icon").attr("title"))
                ?? "Hoster"
            push(redirectPath: target, langKey: langKey, name: name)
        }

        if hosters.isEmpty {
            for a in try doc.select("a[href*=redirect]").array() {
                let href = (try? a.attr("href")) ?? ""
                let parent = a.parent()
                let langKey = (try? parent?.attr("data-lang-key")).flatMap { $0.isEmpty ? nil : $0 } ?? "1"
                let name =
                    (try? a.select("h4").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (try? a.select("i.icon").attr("title"))
                    ?? "Hoster"
                push(redirectPath: href, langKey: langKey, name: name)
            }
        }

        return WatchInfo(path: path, title: h1, germanTitle: germanTitle, englishTitle: englishTitle, hosters: hosters)
    }

    static func langLabel(_ key: String) -> String {
        switch key {
        case "1": return "DE"
        case "2": return "EN"
        case "3": return "GerSub"
        default: return key
        }
    }

    static func slugFromHref(_ href: String) -> String? {
        let cleaned = href.replacingOccurrences(of: "&", with: "&")
        if let m = cleaned.range(of: #"/anime/stream/([^/?#]+)"#, options: .regularExpression) {
            return String(cleaned[m]).split(separator: "/").last.map(String.init)
        }
        if let m = cleaned.range(of: #"/serie/([^/?#]+)"#, options: .regularExpression) {
            return String(cleaned[m]).split(separator: "/").last.map(String.init)
        }
        return nil
    }

    static func parseCatalogSerienstream(_ html: String) throws -> [CatalogItem] {
        let doc = try SwiftSoup.parse(html)
        var seen: [String: CatalogItem] = [:]
        var dropped = Set<String>()
        var usedGenre = false
        let dropGenres: Set<String> = ["anime", "animation", "zeichentrick"]

        func ingest(a: Element, genre: String?, drop: Bool) throws {
            let href = try a.attr("href")
            if href.contains("staffel-") || href.contains("episode-") || href.contains("/filme") { return }
            guard let slug = slugFromHref(href), !slug.isEmpty else { return }
            if drop {
                dropped.insert(slug)
                return
            }
            let title = try a.text().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            if var existing = seen[slug] {
                if let genre, !existing.genres.contains(genre) {
                    existing.genres.append(genre)
                    seen[slug] = existing
                }
                return
            }
            let search = ((try? a.parent()?.attr("data-search")) ?? "").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let alts = unique(
                search.split { $0 == "|" || $0 == "," }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.lowercased() != title.lowercased() }
            ).prefix(8).map { $0 }
            seen[slug] = CatalogItem(slug: slug, title: title, alts: alts, genres: genre.map { [$0] } ?? [])
        }

        for h3 in try doc.select("h3").array() {
            let genre = try h3.text().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if genre.isEmpty || genre.lowercased().hasPrefix("filter.") { continue }
            guard let parent = h3.parent() else { continue }
            var list: Element?
            var sibling = try parent.nextElementSibling()
            while let node = sibling {
                if try node.tagName() == "ul" && node.className().contains("series-list") {
                    list = node
                    break
                }
                sibling = try node.nextElementSibling()
            }
            guard let list else { continue }
            usedGenre = true
            let drop = dropGenres.contains(genre.lowercased())
            for a in try list.select("li.series-item a[href*=/serie/]").array() {
                try ingest(a: a, genre: genre, drop: drop)
            }
        }

        if !usedGenre {
            for a in try doc.select("li.series-item a[href*=/serie/]").array() {
                try ingest(a: a, genre: nil, drop: false)
            }
            return dropAnimeTitles(Array(seen.values))
        }
        return dropAnimeTitles(seen.values.filter { !dropped.contains($0.slug) })
    }

    static func dropAnimeTitles(_ items: [CatalogItem]) -> [CatalogItem] {
        let re = try? NSRegularExpression(
            pattern: #"\b(anime|ova|ona|shounen|shoujo|seinen|isekai|zeichentrick|the animation)\b"#,
            options: [.caseInsensitive]
        )
        return items.filter { item in
            let hay = "\(item.title) \(item.alts.joined(separator: " ")) \(item.genres.joined(separator: " "))"
            let range = NSRange(hay.startIndex..<hay.endIndex, in: hay)
            if re?.firstMatch(in: hay, options: [], range: range) != nil { return false }
            return hay.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value) } == false
        }
    }

    static func parseSeriesSerienstream(_ html: String, slug: String, requestedSeason: String?) throws -> SeriesDetail {
        let doc = try SwiftSoup.parse(html)
        let title = try doc.select("h1").first()?.text()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? slug

        let visibleDescription = try doc.select(".description-text").first()?.text()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let metaDescription = try doc.select("meta[name=description]").attr("content")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let description = visibleDescription.nilIfEmpty ?? metaDescription

        var coverPath: String?
        let poster = try doc.select("img[src*=/media/images/channel/desktop/]").first()?.attr("src") ?? ""
        if poster.hasPrefix("/media/") {
            coverPath = poster.split(separator: "?").first.map(String.init)
        } else {
            let og = try doc.select("meta[property=og:image]").attr("content")
            if og.contains("/media/images/"), let url = URL(string: og) {
                coverPath = url.path
            }
        }

        var seasons: [SeasonRef] = []
        var seen = Set<String>()
        for a in try doc.select("a[href*=/serie/\(slug)/]").array() {
            let href = try a.attr("href")
            if href.contains("/filme") {
                if !seen.contains("filme") {
                    seen.insert("filme")
                    seasons.append(SeasonRef(id: "filme", label: "Filme"))
                }
                continue
            }
            if let m = href.range(of: #"staffel-(\d+)"#, options: .regularExpression) {
                let id = String(href[m]).split(separator: "-").last.map(String.init) ?? ""
                if !id.isEmpty, !seen.contains(id) {
                    seen.insert(id)
                    seasons.append(SeasonRef(id: id, label: "Staffel \(id)"))
                }
            }
        }
        seasons.sort {
            if $0.id == "filme" { return false }
            if $1.id == "filme" { return true }
            return (Int($0.id) ?? 0) < (Int($1.id) ?? 0)
        }
        if seasons.isEmpty { seasons.append(SeasonRef(id: "1", label: "Staffel 1")) }

        var episodes: [Episode] = []
        for row in try doc.select(".episode-row").array() {
            let onclick = (try? row.attr("onclick")) ?? ""
            var href = ""
            if let m = onclick.range(of: #"['"](/serie/[^'"]+)['"]"#, options: .regularExpression) {
                href = String(onclick[m]).replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
            }
            if href.isEmpty {
                href = (try? row.select("a[href*=episode-]").attr("href")) ?? ""
            }
            if href.isEmpty {
                href = (try? row.select("a[href*=/filme/]").attr("href")) ?? ""
            }
            href = href.split(separator: "?").first.map(String.init) ?? href

            let film = href.range(of: #"/filme/(?:film-)?(\d+)"#, options: .regularExpression)
            let episodeMatch = href.range(of: #"episode-(\d+)"#, options: .regularExpression)
            let rowNumber = (try? row.select(".episode-number-cell").text()) ?? ""
            var numRaw = ""
            if let film {
                numRaw = String(href[film]).split(separator: "-").last.map(String.init) ?? ""
            } else if let episodeMatch {
                numRaw = String(href[episodeMatch]).split(separator: "-").last.map(String.init) ?? ""
            } else {
                numRaw = rowNumber
            }
            let number = Int(numRaw.filter { $0.isNumber }) ?? (episodes.count + 1)

            let germanTitle = try row.select(".episode-title-ger").text()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let englishTitle = try row.select(".episode-title-eng").text()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hosters = unique(
                try row.select("img.watch-link, img[alt]").array().compactMap { img -> String? in
                    let t = ((try? img.attr("alt")) ?? (try? img.attr("title")) ?? "")
                        .replacingOccurrences(of: #"^Hoster\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }
            )
            let languages = unique(
                try row.select("svg.watch-language, svg[class*=flag]").array().compactMap { svg -> String? in
                    flagLabel((try? svg.attr("class")) ?? "")
                }
            )
            if href.isEmpty, germanTitle.isEmpty, englishTitle.isEmpty { continue }
            let fallback = film != nil ? "Film \(number)" : "Folge \(number)"
            episodes.append(
                Episode(
                    number: number,
                    germanTitle: germanTitle.isEmpty ? (englishTitle.isEmpty ? fallback : englishTitle) : germanTitle,
                    englishTitle: englishTitle,
                    path: href,
                    hosters: hosters,
                    languages: languages
                )
            )
        }

        var activeSeason = requestedSeason ?? ""
        if activeSeason.isEmpty {
            let href = (try? doc.select("a[href*=/serie/\(slug)/staffel-].active").attr("href")) ?? ""
            if let m = href.range(of: #"staffel-(\d+)"#, options: .regularExpression) {
                activeSeason = String(href[m]).split(separator: "-").last.map(String.init) ?? "1"
            } else {
                activeSeason = seasons.first(where: { $0.id != "filme" })?.id ?? "1"
            }
        }

        return SeriesDetail(
            slug: slug,
            title: title,
            alts: [],
            description: description,
            coverPath: coverPath,
            yearStart: nil,
            yearEnd: nil,
            fsk: nil,
            imdb: nil,
            genres: [],
            seasons: seasons,
            activeSeason: activeSeason,
            episodes: episodes
        )
    }

    static func parseWatchSerienstream(_ html: String, path: String) throws -> WatchInfo {
        let doc = try SwiftSoup.parse(html)
        let h1 = try doc.select("h1").first()?.text()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let germanTitle = (try doc.select(".episode-title-ger").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? h1
        let englishTitle = try doc.select(".episode-title-eng").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var hosters: [HosterOption] = []
        var seen = Set<String>()
        for el in try doc.select("button.link-box[data-play-url]").array() {
            let playUrl = ((try? el.attr("data-play-url")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard playUrl.hasPrefix("/r") else { continue }
            let name = ((try? el.attr("data-provider-name")) ?? (try? el.text()) ?? "Hoster")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let langKey = (try? el.attr("data-language-id")) ?? "1"
            let lang = langLabel(langKey)
            let key = "\(playUrl)|\(langKey)"
            if seen.contains(key) { continue }
            seen.insert(key)
            hosters.append(HosterOption(name: name.isEmpty ? "Hoster" : name, lang: lang, langKey: langKey, redirectPath: playUrl))
        }
        return WatchInfo(path: path, title: h1, germanTitle: germanTitle, englishTitle: englishTitle, hosters: hosters)
    }

    static func parseAniworldCalendar(_ html: String, now: Date = Date()) throws -> CalendarPayload {
        let doc = try SwiftSoup.parse(html)
        var merged: [String: AiringEntry] = [:]
        let months = ["", "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
        for section in try doc.select("section.calendarList").array() {
            let heading = try section.select("h3").first()?.text()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let dateMatch = heading.range(of: #"(\d{1,2})\.(\d{1,2})\.(\d{4})"#, options: .regularExpression) else { continue }
            let nums = String(heading[dateMatch]).split(separator: ".").compactMap { Int($0) }
            guard nums.count == 3 else { continue }
            let day = nums[0], month = nums[1], year = nums[2]
            let dayKey = String(format: "%04d-%02d-%02d", year, month, day)
            let weekday = heading.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let monthName = months.indices.contains(month) ? months[month] : ""
            let dayLabel = "\(weekday), \(day). \(monthName)"
            for a in try section.select("a[href*=anime/stream]").array() {
                guard let slug = slugFromHref(try a.attr("href")) else { continue }
                let title = ((try? a.select("h3.seriesTitle, .seriesTitle, h3").first()?.text()) ?? slug)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let small = (try a.select("small").array().compactMap { try? $0.text() }).joined(separator: " ")
                let blob = "\(small) \(try a.text())"
                var season = "1"
                var episode = 0
                if let m = blob.range(of: #"S(\d+)\s*E(\d+)"#, options: [.regularExpression, .caseInsensitive]) {
                    let parts = String(blob[m]).uppercased().replacingOccurrences(of: "S", with: "").split(separator: "E")
                    if parts.count == 2 {
                        season = String(Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 1)
                        episode = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
                var hour = 0
                var minute = 0
                if let t = small.range(of: #"(\d{1,2}):(\d{2})"#, options: .regularExpression) {
                    let hm = String(small[t]).split(separator: ":")
                    hour = Int(hm.first.map(String.init) ?? "0") ?? 0
                    minute = Int(hm.last.map(String.init) ?? "0") ?? 0
                }
                let airingAt = berlinDate(year: year, month: month, day: day, hour: hour, minute: minute).timeIntervalSince1970 * 1000
                let languages = unique(
                    try a.select("img.flag").array().compactMap { img in
                        flagLabel(((try? img.attr("title")) ?? "") + " " + ((try? img.attr("alt")) ?? "") + " " + ((try? img.attr("src")) ?? ""))
                    }
                )
                let key = "\(slug)|\(season)|\(episode)|\(dayKey)"
                if var existing = merged[key] {
                    existing.languages = unique(existing.languages + languages)
                    merged[key] = existing
                    continue
                }
                merged[key] = AiringEntry(
                    airingAt: airingAt,
                    episode: episode,
                    season: season,
                    title: title.isEmpty ? slug : title,
                    english: nil,
                    slug: slug,
                    languages: languages,
                    dayKey: dayKey,
                    dayLabel: dayLabel
                )
            }
        }
        return packCalendar(Array(merged.values), now: now)
    }

    static func parseSerienstreamCalendar(_ raw: Data, now: Date = Date()) throws -> CalendarPayload {
        let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] ?? [:]
        var merged: [String: AiringEntry] = [:]
        let months = ["", "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
        for (dayKey, rowsAny) in obj {
            let parts = dayKey.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let rows = rowsAny as? [[String: Any]] else { continue }
            let year = parts[0], month = parts[1], day = parts[2]
            let weekday = berlinDate(year: year, month: month, day: day).formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))
            let monthName = months.indices.contains(month) ? months[month] : ""
            let dayLabel = "\(weekday), \(day). \(monthName)"
            for row in rows {
                let url = (row["url"] as? String) ?? ""
                let poster = (row["poster"] as? String) ?? ""
                let slug = slugFromHref(url) ?? poster.split(separator: "-").first.map(String.init) ?? ""
                guard !slug.isEmpty else { continue }
                let time = (row["time"] as? String) ?? "00:00"
                let hm = time.split(separator: ":")
                let hour = Int(hm.first.map(String.init) ?? "0") ?? 0
                let minute = Int(hm.dropFirst().first.map(String.init) ?? "0") ?? 0
                let airingAt = berlinDate(year: year, month: month, day: day, hour: hour, minute: minute).timeIntervalSince1970 * 1000
                let langId = row["language_id"] as? Int
                let langRaw = (row["language"] as? String) ?? ""
                let lang: String? = {
                    if langId == 1 { return "DE" }
                    if langId == 2 { return "EN" }
                    if langId == 3 { return "GerSub" }
                    return flagLabel(langRaw)
                }()
                let season = String((row["season"] as? Int) ?? 1)
                let episode = (row["episode"] as? Int) ?? 0
                let key = "\(slug)|\(season)|\(episode)|\(dayKey)|\(lang ?? "")"
                if var existing = merged[key] {
                    if let lang, !existing.languages.contains(lang) {
                        existing.languages.append(lang)
                        merged[key] = existing
                    }
                    continue
                }
                merged[key] = AiringEntry(
                    airingAt: airingAt,
                    episode: episode,
                    season: season,
                    title: (row["title"] as? String) ?? slug,
                    english: nil,
                    slug: slug,
                    languages: lang.map { [$0] } ?? [],
                    dayKey: dayKey,
                    dayLabel: dayLabel
                )
            }
        }
        return packCalendar(Array(merged.values), now: now)
    }

    static func packCalendar(_ allIn: [AiringEntry], now: Date) -> CalendarPayload {
        let all = allIn.sorted {
            if $0.airingAt != $1.airingAt { return $0.airingAt < $1.airingAt }
            return $0.title.localizedCompare($1.title) == .orderedAscending
        }
        let nowMs = now.timeIntervalSince1970 * 1000
        let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = berlin
        let start = cal.startOfDay(for: now)
        let startToday = start.timeIntervalSince1970 * 1000
        let upcoming = all.filter { $0.airingAt >= nowMs - 3 * 3_600_000 }
        let recent = all.filter { $0.airingAt < nowMs && $0.airingAt >= startToday - 2 * 86_400_000 }
        return CalendarPayload(upcoming: upcoming, recent: recent, fetchedAt: nowMs)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
