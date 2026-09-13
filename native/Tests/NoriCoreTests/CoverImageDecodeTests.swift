import XCTest
@testable import NoriCore
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// Entschlüsseln der Cover abseits des Hauptthreads.
///
/// Geprüft wird die reine Funktion: ein übergroßes Bild kommt verkleinert,
/// ein kleines unverändert, und Bytes, die kein Bild sind, ergeben keins.
final class CoverImageDecodeTests: XCTestCase {
    #if canImport(ImageIO)
    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testOversizedImageIsDownsampledToTheLongestEdge() throws {
        let decoded = try XCTUnwrap(CoverImageLoader.decode(try png(width: 3200, height: 1800), maxPixelSize: 1600))
        XCTAssertEqual(decoded.width, 1600)
        XCTAssertEqual(decoded.height, 900)
    }

    func testSmallImageKeepsItsSize() throws {
        let decoded = try XCTUnwrap(CoverImageLoader.decode(try png(width: 342, height: 513), maxPixelSize: 1600))
        XCTAssertEqual(decoded.width, 342)
        XCTAssertEqual(decoded.height, 513)
    }

    func testHTMLIsNotAnImage() {
        XCTAssertNil(CoverImageLoader.decode(Data("<html>Just a moment…</html>".utf8), maxPixelSize: 1600))
    }

    func testDecodedCacheReturnsTheStoredImage() throws {
        let url = URL(string: "https://image.tmdb.org/t/p/w342/test-\(UUID().uuidString).png")!
        let image = try XCTUnwrap(CoverImageLoader.decode(try png(width: 10, height: 15), maxPixelSize: 1600))
        XCTAssertNil(DecodedImageCache.shared.image(for: url))
        DecodedImageCache.shared.store(image, for: url)
        XCTAssertEqual(DecodedImageCache.shared.image(for: url)?.width, 10)
    }
    #endif
}
