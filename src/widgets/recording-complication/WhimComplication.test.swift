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

    func testCornerWarningIsMonochromeWithTheSameSmallBezelGapAsRecording() throws {
        let entry = WhimComplicationEntry(date: Date(), snapshot: .init(recording: nil, hasFailedNotes: true))
        let (image, pixels) = try render(WhimComplicationContent(entry: entry, family: .accessoryCorner)
            .foregroundStyle(.pink).frame(width: 38, height: 38).background(.black))
        let warningPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] > 200 && pixels[$0 + 2] > 200
        }
        XCTAssertGreaterThan(warningPixels.count, 60, "The white SF Symbol must remain legible")
        let coloredPixels = stride(from: 0, to: pixels.count, by: 4).filter {
            let channels = pixels[$0...($0 + 2)]
            return Int(channels.max()!) - Int(channels.min()!) > 5
        }
        XCTAssertTrue(coloredPixels.isEmpty, "Render the warning in black and white, without a colored tint")
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

    // Break: a fixed 56-point logo overflows the smaller Watch's Corner canvas.
    func testIdleCornerLogoRespectsSmallWatchCanvasSizes() throws {
        let entry = WhimComplicationEntry(date: Date(), snapshot: .idle)
        // Apple specifies 21 pt for a 41 mm Corner image with text, and 34 pt
        // for its circular canvas. Include the adjacent supported Watch sizes.
        for size: CGFloat in [20, 21, 24, 32, 34, 38] {
            let content = WhimCornerComplicationContent(entry: entry, imageBundle: Bundle(for: Self.self))
                .foregroundStyle(.white)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = .init(width: size, height: size)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            // ImageRenderer rounds fractional aspect-fit dimensions up to a pixel.
            XCTAssertLessThanOrEqual(image.width, Int(size * 2) + 1, "Respect the system's Corner width")
            XCTAssertLessThanOrEqual(image.height, Int(size * 2) + 1, "Respect the system's Corner height")

            let (canvas, pixels) = try render(content.frame(width: size, height: size).background(.black))
            let glyphPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 100 }
            XCTAssertGreaterThan(glyphPixels.count, 10, "The compiled logo must remain visible")
            let rows = glyphPixels.map { ($0 / 4) / canvas.width }
            let firstRow = try XCTUnwrap(rows.min())
            let lastRow = try XCTUnwrap(rows.max())
            XCTAssertEqual(Double(firstRow + lastRow) / 2, Double(canvas.height - 1) / 2, accuracy: 1,
                           "Keep the logo centered in the small Corner canvas")
        }
    }

    // Break: the wide full mark does not fit the native Corner image canvas.
    // Compare the rendered complication with the compiled compact artwork so
    // an empty, cropped or incorrect asset cannot pass as a visible logo.
    func testIdleCornerShowsCompleteSmallLogoInTheNativeImageCanvas() throws {
        let entry = WhimComplicationEntry(date: Date(), snapshot: .idle)
        let bundle = Bundle(for: Self.self)
        for size: CGFloat in [20, 21, 24, 32, 34, 38] {
            let reference = Image("whim.small.symbol", bundle: bundle)
                .resizable().scaledToFit()
                .frame(width: min(size, 21), height: min(size, 21))
                .foregroundStyle(.white)
                .frame(width: size, height: size).background(.black)
            let (_, expected) = try render(reference)
            let referenceInk = stride(from: 0, to: expected.count, by: 4).filter { expected[$0] > 100 }
            XCTAssertGreaterThan(referenceInk.count, 10,
                                 "The compact logo must exist in the compiled asset catalog")
            let content = WhimCornerComplicationContent(entry: entry, imageBundle: bundle)
                .foregroundStyle(.white).frame(width: size, height: size)
            let (_, actual) = try render(content.background(.black))
            XCTAssertTrue(actual == expected,
                          "Show the complete compact mark in the native \(size)-point image canvas")
            let (_, masked) = try render(content.clipShape(Circle()).background(.black))
            func coverage(_ values: [UInt8]) -> Double {
                stride(from: 0, to: values.count, by: 4).reduce(0) { $0 + Double(values[$1]) }
            }
            XCTAssertGreaterThan(coverage(masked), coverage(actual) * 0.98,
                                 "The circular face mask must not crop the small logo")
        }
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
