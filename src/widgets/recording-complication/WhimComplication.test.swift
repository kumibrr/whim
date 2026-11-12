import SwiftUI
import WidgetKit
import WhimCore
import XCTest

@MainActor final class WhimComplicationTests: XCTestCase {
    // Break: Whim is absent from the watch face's Corner complication picker.
    func testConfigurationRegistersCornerAlongsideExistingFamilies() {
        let families = WhimComplication.supportedFamilies
        XCTAssertTrue(families.contains(.accessoryCorner), "Whim must be available in Corner slots")
        for family in [WidgetFamily.accessoryCircular, .accessoryRectangular, .accessoryInline] {
            XCTAssertTrue(families.contains(family), "Keep existing \(family) slots available")
        }
    }

    // Break: Corner squeezes Circular's timer above its glyph instead of using the bezel.
    func testCornerRecordingCentersItsGlyphAndReservesTheTimerForTheBezel() throws {
        let date = Date(timeIntervalSince1970: 100)
        let snapshot = ComplicationSnapshot(recording: RecordingProjection(
            sessionID: "session", noteID: "note", source: .appleWatch, createdAt: date), hasFailedNotes: false)
        let (image, pixels) = try render(WhimComplicationContent(
            entry: .init(date: date, snapshot: snapshot), family: .accessoryCorner)
            .frame(width: 38, height: 38).background(.black))
        let redPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] < 100 && pixels[$0 + 2] < 100
        }
        XCTAssertGreaterThan(redPixels.count, 100, "Recording must remain visible")
        let redRows = redPixels.map { ($0 / 4) / image.width }
        let midpoint = Double(try XCTUnwrap(redRows.min()) + XCTUnwrap(redRows.max())) / 2
        XCTAssertEqual(midpoint, Double(image.height - 1) / 2, accuracy: 1,
                       "Corner has one centered glyph; elapsed time belongs on the bezel")
        let whitePixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] > 200 && pixels[$0 + 2] > 200
        }.count
        XCTAssertEqual(whitePixels, 0, "The main Corner content must not contain the Circular timer")
    }

    // Break: Corner uses a straight logo or merely rotates the entire straight mark.
    func testCornerLogoArtworkBendsItsTwoLeadInsInOppositeDirections() throws {
        let (image, pixels) = try render(Image(WhimCornerComplicationContent.logoAssetName, bundle: Bundle(for: Self.self))
            .resizable().scaledToFit().foregroundStyle(.white)
            .frame(width: 304, height: 304).background(.black))
        func meanY(at fraction: Double) throws -> Double {
            let x = Int(Double(image.width) * fraction)
            let rows = (0..<image.height).filter { y in
                let offset = (y * image.width + x) * 4
                return pixels[offset] > 200 && pixels[offset + 1] > 200 && pixels[offset + 2] > 200
            }
            _ = try XCTUnwrap(rows.first, "The Corner logo must be present in the compiled asset catalog")
            return Double(rows.reduce(0, +)) / Double(rows.count)
        }
        let leftSlope = try meanY(at: 0.075) - meanY(at: 0.04)
        let rightSlope = try meanY(at: 0.96) - meanY(at: 0.925)
        XCTAssertGreaterThan(abs(leftSlope), 2, "The left lead-in must follow an arc")
        XCTAssertGreaterThan(abs(rightSlope), 2, "The right lead-out must follow an arc")
        XCTAssertLessThan(leftSlope * rightSlope, 0, "A curved logo has opposing end slopes; rotating a straight logo is insufficient")
    }

    private func render<Content: View>(_ content: Content) throws -> (CGImage, [UInt8]) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (image, pixels)
    }
}
