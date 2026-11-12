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

    // Break: Corner leaves its glyph centered far away from the attached bezel text.
    func testCornerRecordingPlacesItsGlyphNearTheBezelAndKeepsTheTimerSeparate() throws {
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
        let bottomInset = image.height - 1 - (try XCTUnwrap(redRows.max()))
        XCTAssertEqual(Double(bottomInset), 0, accuracy: 1,
                       "Place the glyph at the bezel-facing edge without an extra inset")
        let whitePixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] > 200 && pixels[$0 + 2] > 200
        }.count
        XCTAssertEqual(whitePixels, 0, "The main Corner content must not contain the Circular timer")
    }

    func testCornerWarningUsesTheSameSmallBezelGapAsRecording() throws {
        let entry = WhimComplicationEntry(date: Date(), snapshot: .init(recording: nil, hasFailedNotes: true))
        let (image, pixels) = try render(WhimComplicationContent(entry: entry, family: .accessoryCorner)
            .frame(width: 38, height: 38).background(.black))
        let warningPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] > 140 && pixels[$0 + 2] < 100
        }
        XCTAssertGreaterThan(warningPixels.count, 60, "The warning must remain legible")
        let lastRow = try XCTUnwrap(warningPixels.map { ($0 / 4) / image.width }.max())
        XCTAssertEqual(Double(image.height - 1 - lastRow), 0, accuracy: 1,
                       "Warning and Stop should sit equally close to their curved labels")
    }

    func testCornerLabelMovesOutwardToMeetTheGlyph() throws {
        let entry = WhimComplicationEntry(date: Date(), snapshot: .idle)
        let (image, pixels) = try render(WhimCornerComplicationLabel(entry: entry)
            .font(.system(size: 14)).foregroundStyle(.white)
            .frame(width: 120, height: 40, alignment: .bottom).background(.black))
        let rows = (0..<image.height).filter { y in
            (0..<image.width).contains { x in pixels[(y * image.width + x) * 4] > 200 }
        }
        let lastRow = try XCTUnwrap(rows.max())
        let baselineClearance = image.height - 1 - lastRow
        XCTAssertGreaterThanOrEqual(baselineClearance, 16, "Bring the curved label nearly flush with the glyph")
        XCTAssertLessThanOrEqual(baselineClearance, 18, "Keep the label within its allotted space")
    }

    // Break: Corner uses a straight logo or merely rotates the entire straight mark.
    func testCornerLogoArtworkBendsItsTwoLeadInsInOppositeDirections() throws {
        let (image, pixels) = try renderLogoArtwork()
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

    // Break: extending the curved logo retains blunt, constant-width ends.
    func testCornerLogoHasLongTaperedWedgesAtBothEnds() throws {
        let (image, pixels) = try renderLogoArtwork()
        func thickness(at fraction: Double) -> Double {
            let x = Int(Double(image.width) * fraction)
            return Double((0..<image.height).filter { y in
                let offset = (y * image.width + x) * 4
                return pixels[offset] > 200 && pixels[offset + 1] > 200 && pixels[offset + 2] > 200
            }.count)
        }
        for (tip, base) in [(0.04, 0.09), (0.96, 0.91)] {
            XCTAssertGreaterThan(thickness(at: tip), 0, "Each extended tip must remain visible")
            XCTAssertLessThan(thickness(at: tip), thickness(at: base) * 0.65,
                              "The long ends must taper into wedges rather than round off at full width")
        }
    }

    private func renderLogoArtwork() throws -> (CGImage, [UInt8]) {
        try render(Image(WhimCornerComplicationContent.logoAssetName, bundle: Bundle(for: Self.self))
            .resizable().scaledToFit().foregroundStyle(.white)
            .frame(width: 304, height: 304).background(.black))
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
