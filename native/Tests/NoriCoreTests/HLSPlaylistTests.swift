import XCTest
@testable import NoriCore

/// Die Qualitätsauswahl des Players hängt allein an dieser Auswertung. Zeigt
/// sie Stufen, die es nicht gibt, ist die Auswahl gelogen; übersieht sie
/// welche, fehlt eine Funktion. Beides fällt in der App nicht auf — die Menge
/// der Stufen sieht man erst, wenn man sie mit dem Stream vergleicht.
final class HLSPlaylistTests: XCTestCase {
    /// Eine Master-Playlist, wie die Hoster sie ausliefern.
    private let master = """
    #EXTM3U
    #EXT-X-STREAM-INF:BANDWIDTH=5100000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
    1080/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
    720/index.m3u8
    #EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=854x480,CODECS="avc1.4d401e,mp4a.40.2"
    480/index.m3u8
    """

    func testReadsEveryVariantHighestFirst() {
        let variants = HLSPlaylist.parse(master)
        XCTAssertEqual(variants.map(\.height), [1080, 720, 480])
        XCTAssertEqual(variants.map(\.label), ["1080p", "720p", "480p"])
    }

    /// Eine Medien-Playlist ist keine Auswahl: sie beschreibt genau eine Spur.
    func testMediaPlaylistOffersNothing() {
        let media = """
        #EXTM3U
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        segment0.ts
        #EXTINF:10.0,
        segment1.ts
        """
        XCTAssertTrue(HLSPlaylist.parse(media).isEmpty)
    }

    /// Eine einzige Stufe ist ebenfalls keine Auswahl. Ein Menü mit einem
    /// Eintrag ist ein toter Knopf.
    func testSingleVariantOffersNothing() {
        let single = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720
        720/index.m3u8
        """
        XCTAssertTrue(HLSPlaylist.parse(single).isEmpty)
    }

    /// `CODECS` steht in Anführungszeichen und enthält Kommas. Wer die
    /// Attributliste an Kommas zerlegt, liest danach Unsinn — und `RESOLUTION`
    /// hinter `CODECS` gar nicht mehr.
    func testCommaInsideQuotedAttributeDoesNotConfuseTheParser() {
        let tricky = """
        #EXTM3U
        #EXT-X-STREAM-INF:CODECS="avc1.640028,mp4a.40.2",BANDWIDTH=5100000,RESOLUTION=1920x1080
        a.m3u8
        #EXT-X-STREAM-INF:CODECS="avc1.4d401f,mp4a.40.2",BANDWIDTH=900000,RESOLUTION=854x480
        b.m3u8
        """
        let variants = HLSPlaylist.parse(tricky)
        XCTAssertEqual(variants.map(\.height), [1080, 480])
        XCTAssertEqual(variants.first?.bandwidth, 5_100_000)
    }

    /// Ohne `RESOLUTION` bleibt die Bitrate als Unterscheidung. „5,1 Mbit/s"
    /// sagt weniger als „1080p", aber immer noch genug, um zu wählen.
    func testFallsBackToBitrateLabelWithoutResolution() {
        let noResolution = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5100000
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=900000
        b.m3u8
        """
        let variants = HLSPlaylist.parse(noResolution)
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants.map(\.height), [nil, nil])
        XCTAssertTrue(variants[0].label.contains("Mbit/s"))
    }

    /// Dieselbe Auflösung mehrfach — etwa je Tonspur — ist eine Stufe, keine
    /// drei. Es bleibt die mit der höchsten Bitrate.
    func testDuplicateResolutionsCollapseToTheBestOne() {
        let duplicates = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5100000,RESOLUTION=1920x1080,AUDIO="de"
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,AUDIO="en"
        b.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=854x480,AUDIO="de"
        c.m3u8
        """
        let variants = HLSPlaylist.parse(duplicates)
        XCTAssertEqual(variants.count, 2)
        XCTAssertEqual(variants.first?.bandwidth, 5_100_000)
    }

    /// Zeilen ohne Bandbreite sind unbrauchbar — `BANDWIDTH` ist in HLS
    /// Pflicht, und ohne sie lässt sich die Stufe weder benennen noch
    /// erzwingen.
    func testVariantWithoutBandwidthIsIgnored() {
        let broken = """
        #EXTM3U
        #EXT-X-STREAM-INF:RESOLUTION=1920x1080
        a.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=854x480
        b.m3u8
        """
        // Nur eine verwertbare Stufe übrig — und eine ist keine Auswahl.
        XCTAssertTrue(HLSPlaylist.parse(broken).isEmpty)
    }
}
