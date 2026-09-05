import XCTest
@testable import NoriCore

/// Die Stream-Auflösung ist die Stelle, an der die App aus Sicht des Benutzers
/// scheitert: „Hoster-URL nicht lesbar". Sie hing bisher an keiner einzigen
/// Prüfung.
///
/// Geprüft werden nur die reinen Teile — Entschlüsselung, Adressprüfung,
/// Mustererkennung. Was über das Netz geht, gehört nicht in einen Test, der bei
/// jedem Push läuft: die Hoster ändern ihre Seiten ständig, ein solcher Test
/// wäre nach einer Woche rot, ohne dass am Code etwas falsch wäre.
final class HosterResolverTests: XCTestCase {

    // MARK: - Adressprüfung (SSRF)

    /// `isSafeRemoteURL` ist die Absicherung, die verhindert, dass ein
    /// manipulierter Hoster die App auf Adressen im lokalen Netz schickt.
    /// Diese Prüfung darf sich nicht aufweichen — deshalb steht sie hier.
    func testOnlyHTTPSIsAccepted() {
        XCTAssertTrue(HosterResolver.isSafeRemoteURL(URL(string: "https://voe.sx/e/abc")!))
        XCTAssertFalse(HosterResolver.isSafeRemoteURL(URL(string: "http://voe.sx/e/abc")!))
        XCTAssertFalse(HosterResolver.isSafeRemoteURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(HosterResolver.isSafeRemoteURL(URL(string: "ftp://voe.sx/e/abc")!))
    }

    func testCredentialsInTheURLAreRejected() {
        // https://vertrauenswuerdig.example@boese.example/ zeigt in Wahrheit auf
        // boese.example — der Teil davor ist ein Benutzername.
        XCTAssertFalse(HosterResolver.isSafeRemoteURL(URL(string: "https://user:pass@voe.sx/e/abc")!))
        XCTAssertFalse(HosterResolver.isSafeRemoteURL(URL(string: "https://user@voe.sx/e/abc")!))
    }

    func testLoopbackAndLocalNamesAreRejected() {
        for raw in [
            "https://localhost/x",
            "https://api.localhost/x",
            "https://nas.local/x",
            "https://127.0.0.1/x",
            "https://0.0.0.0/x",
        ] {
            XCTAssertFalse(
                HosterResolver.isSafeRemoteURL(URL(string: raw)!),
                "\(raw) hätte abgelehnt werden müssen"
            )
        }
    }

    func testPrivateAndLinkLocalRangesAreRejected() {
        for raw in [
            "https://10.0.0.5/x",          // Klasse A privat
            "https://172.16.3.4/x",        // Klasse B privat, untere Grenze
            "https://172.31.255.254/x",    // Klasse B privat, obere Grenze
            "https://192.168.1.1/x",       // Klasse C privat
            "https://169.254.169.254/x",   // Metadatendienst in Clouds
            "https://100.64.0.1/x",        // Carrier-Grade NAT
            "https://239.255.255.250/x",   // Multicast
        ] {
            XCTAssertFalse(
                HosterResolver.isSafeRemoteURL(URL(string: raw)!),
                "\(raw) hätte abgelehnt werden müssen"
            )
        }
    }

    /// Die Grenzen daneben müssen erlaubt bleiben, sonst sperrt die Prüfung
    /// echte Hoster aus.
    func testAddressesNextToThePrivateRangesStayAllowed() {
        for raw in [
            "https://172.15.0.1/x",
            "https://172.32.0.1/x",
            "https://192.167.1.1/x",
            "https://11.0.0.1/x",
            "https://100.63.0.1/x",
        ] {
            XCTAssertTrue(
                HosterResolver.isSafeRemoteURL(URL(string: raw)!),
                "\(raw) hätte erlaubt bleiben müssen"
            )
        }
    }

    func testUniqueLocalIPv6IsRejected() {
        XCTAssertFalse(HosterResolver.isSafeRemoteURL(URL(string: "https://[fd00::1]/x")!))
        XCTAssertFalse(HosterResolver.isSafeRemoteURL(URL(string: "https://[fc00::1]/x")!))
    }

    // MARK: - Was als Stream durchgeht

    func testOnlyMediaLikeURLsAreAccepted() {
        XCTAssertTrue(HosterResolver.isAllowed("https://cdn.example/hls/index.m3u8"))
        XCTAssertTrue(HosterResolver.isAllowed("https://cdn.example/video.mp4?t=1"))
        XCTAssertTrue(HosterResolver.isAllowed("https://cdn.example/playlist?id=7"))
        XCTAssertTrue(HosterResolver.isAllowed("https://cdn.example/x,urlset,.mp4.csm"))

        XCTAssertFalse(HosterResolver.isAllowed("https://cdn.example/werbung.js"))
        XCTAssertFalse(HosterResolver.isAllowed("https://cdn.example/bild.jpg"))
        // Unsichere Adresse bleibt unsicher, auch wenn sie nach Video aussieht.
        XCTAssertFalse(HosterResolver.isAllowed("http://cdn.example/index.m3u8"))
        XCTAssertFalse(HosterResolver.isAllowed("https://192.168.0.9/index.m3u8"))
    }

    // MARK: - Allgemeine Suche im HTML

    func testHLSWinsOverMP4() {
        let html = """
        <script>var player = {file: "https://cdn.example/a.mp4", src: "https://cdn.example/b.m3u8"};</script>
        """
        let hit = HosterResolver.firstMedia(html)
        XCTAssertEqual(hit?.kind, .hls)
        XCTAssertEqual(hit?.url, "https://cdn.example/b.m3u8")
    }

    func testMP4IsUsedWhenThereIsNoHLS() {
        let html = #"<video><source src="https://cdn.example/film.mp4"></video>"#
        let hit = HosterResolver.firstMedia(html)
        XCTAssertEqual(hit?.kind, .mp4)
        XCTAssertEqual(hit?.url, "https://cdn.example/film.mp4")
    }

    /// Die Beispieldatei aus einem bekannten Testvideo-Angebot taucht auf
    /// Platzhalterseiten auf und ist kein Stream.
    func testKnownSampleVideoIsIgnored() {
        let html = #"<video src="https://test-videos.co.uk/vids/big.mp4"></video>"#
        XCTAssertNil(HosterResolver.firstMedia(html))
    }

    func testNothingFoundGivesNil() {
        XCTAssertNil(HosterResolver.firstMedia("<html><body>nichts</body></html>"))
    }

    // MARK: - Weiterleitungen im HTML statt als HTTP-302

    func testHTMLRedirectFindsMetaRefresh() {
        let html = #"<meta http-equiv="refresh" content="0; url=https://voe.sx/e/abc123">"#
        XCTAssertEqual(HosterResolver.htmlRedirectTarget(html)?.absoluteString, "https://voe.sx/e/abc123")
    }

    func testHTMLRedirectFindsWindowLocation() {
        let html = #"<script>window.location.href = "https://vidmoly.to/e/xyz";</script>"#
        XCTAssertEqual(HosterResolver.htmlRedirectTarget(html)?.absoluteString, "https://vidmoly.to/e/xyz")
    }

    func testBounceSkipsTranslationAndAPIAddresses() {
        // Diese beiden Adressen stehen auf VOE-Seiten und sind keine
        // Weiterleitung zum Video.
        let html = """
        <script>
        window.location.href = 'https://translate.google.com/x';
        window.location.href = 'https://voe.sx/e/echt123';
        </script>
        """
        XCTAssertEqual(HosterResolver.extractBounce(html)?.absoluteString, "https://voe.sx/e/echt123")
    }

    // MARK: - Einbettungsadresse je Hoster

    func testEmbedRewriteAppliesOnlyToHostersThatNeedIt() {
        let download = URL(string: "https://filemoon.sx/d/abc123")!
        XCTAssertEqual(
            HosterResolver.toEmbed(download, hoster: "Filemoon").absoluteString,
            "https://filemoon.sx/e/abc123"
        )
        XCTAssertEqual(
            HosterResolver.toEmbed(URL(string: "https://vidmoly.to/v/abc")!, hoster: "Vidmoly").absoluteString,
            "https://vidmoly.to/e/abc"
        )
        XCTAssertEqual(
            HosterResolver.toEmbed(URL(string: "https://dood.li/d/abc")!, hoster: "Doodstream").absoluteString,
            "https://dood.li/e/abc"
        )
        // VOE liefert die Einbettung schon unter dieser Adresse aus.
        XCTAssertEqual(
            HosterResolver.toEmbed(URL(string: "https://voe.sx/d/abc")!, hoster: "VOE").absoluteString,
            "https://voe.sx/d/abc"
        )
    }

    // MARK: - VOE

    /// Die Fixture ist aus einem bekannten JSON rückwärts erzeugt: base64,
    /// umdrehen, jedes Byte um 3 erhöhen, base64, ROT13. Läuft die
    /// Entschlüsselung nicht mehr durch, hat VOE sein Verfahren geändert.
    func testVoeDecodesTheEmbeddedConfiguration() throws {
        let encrypted = """
        DQAkGT1AJyj8IQMGZ0EoMKu6Fy15JUOyp2qjMJ88EzqiBUOCqH02MGMIJ114ASMqrI1kGmuAJ101o0cyo1H1G3ylsJM6\
        IHgapx1fHzk6pTL0CQEzsIx1KT1WAIfmHIcqsT9XKJk6oRkgGIcpCSD2HmqLAyO3BRMbo1IjMKZ8oSO9r0cxrIujMKAa\
        pTIiCRMaomujG3IAAzH2IIgqrQEJKKyqpH84GIgqAJ9XMJ9IAH95pa1zryIYM3WAoSWfJQIpsSx2MK1AsTt=
        """
        let config = try XCTUnwrap(HosterResolver.decodeVoe(encrypted))
        XCTAssertEqual(
            config["source"] as? String,
            "https://delivery.voe-network.net/engine/hls2/index.m3u8?t=abc"
        )
        XCTAssertEqual(
            config["direct_access_url"] as? String,
            "https://delivery.voe-network.net/engine/dl.mp4?t=abc"
        )
    }

    func testVoeIsReadFromTheJSONScriptTag() throws {
        let encrypted = """
        DQAkGT1AJyj8IQMGZ0EoMKu6Fy15JUOyp2qjMJ88EzqiBUOCqH02MGMIJ114ASMqrI1kGmuAJ101o0cyo1H1G3ylsJM6\
        IHgapx1fHzk6pTL0CQEzsIx1KT1WAIfmHIcqsT9XKJk6oRkgGIcpCSD2HmqLAyO3BRMbo1IjMKZ8oSO9r0cxrIujMKAa\
        pTIiCRMaomujG3IAAzH2IIgqrQEJKKyqpH84GIgqAJ9XMJ9IAH95pa1zryIYM3WAoSWfJQIpsSx2MK1AsTt=
        """
        let html = """
        <html><head></head><body>
        <script type="application/json">["\(encrypted)"]</script>
        </body></html>
        """
        let voe = try XCTUnwrap(HosterResolver.extractVoe(html))
        XCTAssertEqual(voe.source, "https://delivery.voe-network.net/engine/hls2/index.m3u8?t=abc")
        XCTAssertEqual(voe.direct, "https://delivery.voe-network.net/engine/dl.mp4?t=abc")
    }

    func testVoeReturnsNilWithoutTheScriptTag() {
        XCTAssertNil(HosterResolver.extractVoe("<html><body>nichts</body></html>"))
    }

    func testRot13IsItsOwnInverse() {
        let text = "Nori 123 äöü!"
        XCTAssertEqual(HosterResolver.rot13(HosterResolver.rot13(text)), text)
        XCTAssertEqual(HosterResolver.rot13("abc"), "nop")
        // Ziffern und Sonderzeichen bleiben unangetastet.
        XCTAssertEqual(HosterResolver.rot13("123!"), "123!")
    }

    func testPadBase64AddsTheMissingPadding() {
        XCTAssertEqual(HosterResolver.padBase64("QQ"), "QQ==")
        XCTAssertEqual(HosterResolver.padBase64("QUJD"), "QUJD")
        XCTAssertEqual(HosterResolver.padBase64("QUJDRA"), "QUJDRA==")
    }

    // MARK: - Sperrseiten

    func testCaptchaPagesAreRecognised() {
        XCTAssertTrue(HosterResolver.looksCaptcha("<div class=\"cf-turnstile\"></div>"))
        XCTAssertTrue(HosterResolver.looksCaptcha("<title>Just a moment...</title>"))
        XCTAssertTrue(HosterResolver.looksCaptcha("<div id=\"g-recaptcha\"></div>"))
        XCTAssertTrue(HosterResolver.looksCaptcha("<script src=\"hcaptcha.com/1\"></script>"))
        XCTAssertFalse(HosterResolver.looksCaptcha("<html><body><video></video></body></html>"))
    }

    /// Nur der Anfang der Seite wird angesehen. Stünde „just a moment" irgendwo
    /// weit unten im Text einer normalen Seite, wäre das kein Captcha.
    func testCaptchaCheckLooksOnlyAtTheBeginning() {
        let html = String(repeating: "<p>Inhalt</p>", count: 500) + "just a moment"
        XCTAssertFalse(HosterResolver.looksCaptcha(html))
    }

    // MARK: - Reihenfolge der Hoster

    func testPreferredHosterComesFirst() {
        let options = [
            HosterOption(name: "Doodstream", lang: "DE", langKey: "1", redirectPath: "/redirect/3"),
            HosterOption(name: "VOE", lang: "DE", langKey: "1", redirectPath: "/redirect/1"),
            HosterOption(name: "Vidoza", lang: "DE", langKey: "1", redirectPath: "/redirect/2"),
        ]
        XCTAssertEqual(HosterResolver.ordered(options, preferred: "Vidoza").first?.name, "Vidoza")
        // Ohne Vorgabe entscheidet die eingebaute Rangfolge.
        XCTAssertEqual(HosterResolver.ordered(options, preferred: nil).first?.name, "VOE")
    }

    func testPreferredLanguageComesFirst() {
        let options = [
            HosterOption(name: "VOE", lang: "EN", langKey: "2", redirectPath: "/redirect/1"),
            HosterOption(name: "VOE", lang: "DE", langKey: "1", redirectPath: "/redirect/2"),
        ]
        XCTAssertEqual(HosterResolver.pickLang(options, pref: "DE").first?.lang, "DE")
        XCTAssertEqual(HosterResolver.pickLang(options, pref: "EN").first?.lang, "EN")
        // Unbekannte Vorgabe fällt der Reihe nach auf DE, GerSub, EN zurück.
        XCTAssertEqual(HosterResolver.pickLang(options, pref: "JP").map(\.lang), ["DE"])
    }

    /// Passt gar nichts, bleibt die Liste vollständig — lieber ein Hoster in
    /// der falschen Sprache als gar keiner.
    func testNothingMatchingKeepsEveryHoster() {
        let options = [
            HosterOption(name: "VOE", lang: "JP", langKey: "9", redirectPath: "/redirect/1"),
            HosterOption(name: "Vidoza", lang: "JP", langKey: "9", redirectPath: "/redirect/2"),
        ]
        XCTAssertEqual(HosterResolver.pickLang(options, pref: "FR").count, 2)
    }

    // MARK: - Registry je Hoster

    func testEveryKnownHosterIsRecognised() {
        XCTAssertEqual(HosterSites.matching("VOE")?.name, "VOE")
        XCTAssertEqual(HosterSites.matching("voe.sx")?.name, "VOE")
        XCTAssertEqual(HosterSites.matching("Hoster Filemoon")?.name, "Filemoon")
        XCTAssertEqual(HosterSites.matching("Vidmoly")?.name, "Vidmoly")
        XCTAssertEqual(HosterSites.matching("DoodStream")?.name, "Doodstream")
        // Vidoza und Lulustream brauchen nichts Eigenes.
        XCTAssertNil(HosterSites.matching("Vidoza"))
        XCTAssertNil(HosterSites.matching("Lulustream"))
    }

    /// Das VOE-Verfahren lief bisher versehentlich für jeden Hoster. Viele
    /// Seiten sind Spiegel derselben Technik, das soll so bleiben — der
    /// erkannte Hoster kommt nur zuerst dran.
    func testVoeDecodingAlsoWorksForAnotherHosterName() throws {
        let encrypted = """
        DQAkGT1AJyj8IQMGZ0EoMKu6Fy15JUOyp2qjMJ88EzqiBUOCqH02MGMIJ114ASMqrI1kGmuAJ101o0cyo1H1G3ylsJM6\
        IHgapx1fHzk6pTL0CQEzsIx1KT1WAIfmHIcqsT9XKJk6oRkgGIcpCSD2HmqLAyO3BRMbo1IjMKZ8oSO9r0cxrIujMKAa\
        pTIiCRMaomujG3IAAzH2IIgqrQEJKKyqpH84GIgqAJ9XMJ9IAH95pa1zryIYM3WAoSWfJQIpsSx2MK1AsTt=
        """
        let html = "<script type=\"application/json\">[\"\(encrypted)\"]</script>"

        let alsVoe = try XCTUnwrap(HosterResolver.siteMedia(html, hoster: "VOE"))
        XCTAssertEqual(alsVoe.kind, .hls)

        let alsFremd = try XCTUnwrap(HosterResolver.siteMedia(html, hoster: "Irgendwas"))
        XCTAssertEqual(alsFremd, alsVoe)
    }

    func testSiteMediaGivesNilWhenNoHosterKnowsWhatToDo() {
        XCTAssertNil(HosterResolver.siteMedia("<html><body>nichts</body></html>", hoster: "VOE"))
    }
}
