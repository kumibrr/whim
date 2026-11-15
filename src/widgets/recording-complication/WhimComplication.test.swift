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

    // Break: the native template places the logo and Record on different axes.
    func testIdleCornerAlignsStraightLogoAndCurvedRecordInOneCanvas() throws {
        for (corner, horizontal, vertical, slope): (WhimCornerPosition, Double, Double, Double) in [
            (.topRight, 1, -1, 1), (.topLeft, -1, -1, -1),
            (.bottomRight, 1, 1, -1), (.bottomLeft, -1, 1, 1)
        ] {
            let entry = WhimComplicationEntry(date: Date(), snapshot: .idle, corner: corner)
            let content = WhimCornerComplicationContent(entry: entry, imageBundle: Bundle(for: Self.self))
                .foregroundStyle(.white).frame(width: 34, height: 34)
            let (image, pixels) = try render(content.background(.black), scale: 2)
            let angle = slope * atan2(176.0, 215.0)
            let outward = CGVector(dx: horizontal * abs(sin(angle)), dy: vertical * cos(angle))
            let tangent = CGVector(dx: cos(angle), dy: sin(angle))
            let center = Double(image.width - 1) / 2
            let ink = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 100 }
            func projection(_ offset: Int, onto vector: CGVector) -> Double {
                (Double((offset / 4) % image.width) - center) / 2 * vector.dx
                + (Double((offset / 4) / image.width) - center) / 2 * vector.dy
            }
            let logo = ink.filter { projection($0, onto: outward) > -2 }
            let caption = ink.filter { projection($0, onto: outward) < -2 }
            XCTAssertGreaterThan(logo.count, 10)
            XCTAssertGreaterThan(caption.count, 20, "Draw the curved caption in the same canvas as the logo")
            for (name, group) in [("logo", logo), ("caption", caption)] {
                let positions = group.map { projection($0, onto: tangent) }
                let first = try XCTUnwrap(positions.min()), last = try XCTUnwrap(positions.max())
                XCTAssertEqual((first + last) / 2, 0, accuracy: 1,
                               "Center \(corner) \(name) on the same radial axis")
            }
            let xs = logo.map { ($0 / 4) % image.width }
            let leftX = try XCTUnwrap(xs.min()), rightX = try XCTUnwrap(xs.max())
            func meanY(_ group: [Int]) -> Double {
                Double(group.map { ($0 / 4) / image.width }.reduce(0, +)) / Double(group.count) / 2
            }
            XCTAssertEqual(meanY(logo.filter { ($0 / 4) % image.width <= leftX + 2 }),
                           meanY(logo.filter { ($0 / 4) % image.width >= rightX - 2 }), accuracy: 1,
                           "Keep the logo straight")
            let textPositions = caption.map { projection($0, onto: tangent) }
            let start = try XCTUnwrap(textPositions.min()), end = try XCTUnwrap(textPositions.max())
            XCTAssertGreaterThan(slope * (meanY(caption.filter { projection($0, onto: tangent) > end - 3 })
                                 - meanY(caption.filter { projection($0, onto: tangent) < start + 3 })), 8,
                                 "Keep Record angled along the dial")
            let (_, clipped) = try render(content.clipShape(Circle()).background(.black), scale: 2)
            func coverage(_ values: [UInt8]) -> Double {
                stride(from: 0, to: values.count, by: 4).reduce(0) { $0 + Double(values[$1]) }
            }
            XCTAssertGreaterThan(coverage(clipped), coverage(pixels) * 0.98,
                                 "Keep both elements inside the circular mask")
        }
    }

    // Break: rotating a straight word is not the same as following the dial's arc.
    func testRecordBendsAlongTheDialRatherThanOnlyRotating() throws {
        let entry = WhimComplicationEntry(date: Date(), snapshot: .idle)
        let (image, pixels) = try render(WhimCornerComplicationContent(
            entry: entry, imageBundle: Bundle(for: Self.self))
            .foregroundStyle(.white).frame(width: 34, height: 34).background(.black), scale: 4)
        let angle = atan2(176.0, 215.0)
        let center = Double(image.width - 1) / 2
        var caption = [(along: Double, radial: Double)]()
        for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset] > 100 {
            let x = (Double((offset / 4) % image.width) - center) / 4
            let y = (Double((offset / 4) / image.width) - center) / 4
            let radial = x * sin(angle) - y * cos(angle)
            if radial < -2 { caption.append((x * cos(angle) + y * sin(angle), radial)) }
        }
        let first = try XCTUnwrap(caption.map(\.along).min())
        let last = try XCTUnwrap(caption.map(\.along).max())
        let leading = try XCTUnwrap(caption.filter { $0.along < first + 5.5 }.map(\.radial).max())
        let trailing = try XCTUnwrap(caption.filter { $0.along > last - 5.5 }.map(\.radial).max())
        let middle = try XCTUnwrap(caption.filter { abs($0.along) < 3 }.map(\.radial).max())
        XCTAssertGreaterThan(middle - (leading + trailing) / 2, 0.35,
                             "Both ends must bend inward from the middle of the curved caption")
    }

    func testStatusLabelRetainsItsBezelGap() throws {
        let entry = WhimComplicationEntry(date: Date(), snapshot: .init(recording: nil, hasFailedNotes: true))
        let (image, pixels) = try render(WhimCornerComplicationLabel(entry: entry)
            .font(.system(size: 14)).foregroundStyle(.white)
            .frame(width: 120, height: 40, alignment: .bottom).background(.black))
        let rows = (0..<image.height).filter { y in
            (0..<image.width).contains { x in pixels[(y * image.width + x) * 4] > 200 }
        }
        let lastRow = try XCTUnwrap(rows.max())
        XCTAssertEqual(Double(image.height - 1 - lastRow), 17, accuracy: 1,
                       "Keep the attention label close to its status glyph")
    }

    // Break: a fixed 56-point logo overflows the smaller Watch's Corner canvas.
    func testIdleCornerLogoRespectsSmallWatchCanvasSizes() throws {
        // Apple specifies 21 pt for a 41 mm Corner image with text, and 34 pt
        // for its circular canvas. Include the adjacent supported Watch sizes.
        for size: CGFloat in [20, 21, 24, 32, 34, 38] {
            let content = WhimCornerLogo(imageBundle: Bundle(for: Self.self))
                .foregroundStyle(.white)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = .init(width: size, height: size)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            // ImageRenderer rounds fractional aspect-fit dimensions up to a pixel.
            XCTAssertLessThanOrEqual(image.width, Int(size * 2) + 1, "Respect the system's Corner width")
            XCTAssertLessThanOrEqual(image.height, Int(size * 2) + 1, "Respect the system's Corner height")

            let (canvas, pixels) = try render(content.frame(width: size, height: size).background(.black))
            let (_, maskedPixels) = try render(content.frame(width: size, height: size)
                .clipShape(Circle()).background(.black))
            func coverage(_ values: [UInt8]) -> Double {
                stride(from: 0, to: values.count, by: 4).reduce(0.0) { $0 + Double(values[$1]) / 255 }
            }
            XCTAssertGreaterThan(coverage(maskedPixels), coverage(pixels) * 0.98,
                                 "Keep the complete compact mark inside the system's circular mask")
            let glyphPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 100 }
            XCTAssertGreaterThan(glyphPixels.count, 10, "The compiled logo must remain visible")
            let rows = glyphPixels.map { ($0 / 4) / canvas.width }
            let firstRow = try XCTUnwrap(rows.min())
            let lastRow = try XCTUnwrap(rows.max())
            XCTAssertEqual(Double(firstRow + lastRow) / 2, Double(canvas.height - 1) / 2, accuracy: 1,
                           "Keep the logo centered in the small Corner canvas")
        }
    }

    // Break: recording expiry drops the failed-Note attention state.
    func testRecordingExpirationPreservesFailedNoteAttention() {
        let date = Date(timeIntervalSince1970: 100)
        let recording = RecordingProjection(sessionID: "session", noteID: "note", source: .appleWatch,
                                            createdAt: date)
        let provider = WhimComplicationProvider(loadSnapshot: {
            .init(recording: recording, hasFailedNotes: true)
        })
        let entries = provider.entries(at: date)
        XCTAssertEqual(entries.map(\.date), [date, Date(timeIntervalSince1970: 400)])
        XCTAssertNotNil(entries.first?.snapshot.activeRecording(at: date))
        XCTAssertNil(entries.last?.snapshot.activeRecording(at: Date(timeIntervalSince1970: 400)))
        XCTAssertEqual(entries.last?.snapshot.hasFailedNotes, true)
    }

    func testCornerSelectionSurvivesRefreshAndRecordingExpiration() {
        let date = Date(timeIntervalSince1970: 100)
        let recording = RecordingProjection(sessionID: "session", noteID: "note", source: .appleWatch, createdAt: date)
        for corner in WhimCornerPosition.allCases {
            let provider = WhimComplicationProvider(corner: corner, loadSnapshot: {
                .init(recording: recording, hasFailedNotes: false)
            })
            XCTAssertEqual(provider.entries(at: date).map(\.corner), [corner, corner])
        }
    }

    func testCornerPickerPreservesExistingIdentityAndUsesDistinctKinds() {
        XCTAssertEqual(WhimCornerPosition.topRight.widgetKind, "app.whim.recording")
        XCTAssertEqual(Set(WhimCornerPosition.allCases.map(\.widgetKind)).count, 4)
    }

    // Break: interpolated display names crash WidgetKit while it discovers the widgets.
    func testConfigurationBuildsWithoutFormattedMetadata() {
        _ = WhimComplication().body
        _ = WhimTopLeftComplication().body
        _ = WhimBottomRightComplication().body
        _ = WhimBottomLeftComplication().body
    }

    private func render<Content: View>(_ content: Content, scale: CGFloat = 1) throws -> (CGImage, [UInt8]) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
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
