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

    func testCompleteLogoUsesAWiderCornerWithoutWideningStatusIcons() throws {
        let date = Date()
        let recording = RecordingProjection(sessionID: "session", noteID: "note", source: .appleWatch, createdAt: date)
        let cases: [(ComplicationSnapshot, Int)] = [
            (.idle, 56),
            (.init(recording: recording, hasFailedNotes: false), 38),
            (.init(recording: nil, hasFailedNotes: true), 38),
        ]
        for (snapshot, expectedWidth) in cases {
            let renderer = ImageRenderer(content: WhimCornerComplicationContent(entry: .init(date: date, snapshot: snapshot))
                .frame(height: 38).background(.black))
            renderer.proposedSize = .init(width: 38, height: 38)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, expectedWidth, "The complete logo should claim the available horizontal space")
        }
    }

    func testCompleteCornerLogoFollowsAGentleArc() throws {
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
        let leftRise = try meanY(at: 0.06) - meanY(at: 0.14)
        let rightRise = try meanY(at: 0.94) - meanY(at: 0.86)
        for rise in [leftRise, rightRise] {
            XCTAssertGreaterThan(abs(rise), 4, "Warp the complete logo along the label's arc")
            XCTAssertLessThan(abs(rise), 9, "Keep the bend gentle at the rounded ends")
        }
        XCTAssertGreaterThan(leftRise * rightRise, 0, "Both ends follow the same arc")
        XCTAssertEqual(leftRise, rightRise, accuracy: 1.5, "Keep the logo centered on the arc")
    }

    // Break: Corner still uses the shortened mark, omitting the full logo's floating dot.
    func testCornerShowsTheCompleteWaveformAndItsFloatingDot() throws {
        let (image, pixels) = try renderLogoArtwork()
        var remaining = Set((0..<(image.width * image.height)).filter { index in
            let offset = index * 4
            return pixels[offset] > 200 && pixels[offset + 1] > 200 && pixels[offset + 2] > 200
        })
        var components = [[Int]]()
        while let first = remaining.first {
            remaining.remove(first)
            var component = [first]
            var cursor = 0
            while cursor < component.count {
                let point = component[cursor]
                let x = point % image.width, y = point / image.width
                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                for (nx, ny) in neighbors where nx >= 0 && nx < image.width && ny >= 0 && ny < image.height {
                    let neighbor = ny * image.width + nx
                    if remaining.remove(neighbor) != nil { component.append(neighbor) }
                }
                cursor += 1
            }
            components.append(component)
        }
        components.sort { $0.count > $1.count }
        XCTAssertEqual(components.count, 2, "Show the continuous full waveform and its separate floating dot")
        guard components.count == 2 else { return }
        let waveform = components[0], dot = components[1]
        XCTAssertGreaterThan(waveform.count, dot.count * 10)
        XCTAssertGreaterThan(dot.count, 15, "The complete logo's dot must remain visible")
        let dotX = Double(dot.map { $0 % image.width }.reduce(0, +)) / Double(dot.count * image.width)
        XCTAssertGreaterThan(dotX, 0.54)
        XCTAssertLessThan(dotX, 0.61, "Keep the floating dot in its original position in the full mark")
    }

    // Break: the extended ends finish in sharp wedge points rather than soft caps.
    func testCornerLogoFinishesWithSoftRoundedEnds() throws {
        let (image, pixels) = try renderLogoArtwork()
        func thickness(at fraction: Double) -> Double {
            let x = Int(Double(image.width) * fraction)
            return Double((0..<image.height).filter { y in
                let offset = (y * image.width + x) * 4
                return pixels[offset] > 200 && pixels[offset + 1] > 200 && pixels[offset + 2] > 200
            }.count)
        }
        for (edge, cap, base) in [(0.003, 0.015, 0.1), (0.997, 0.985, 0.9)] {
            XCTAssertGreaterThan(thickness(at: edge), 0, "Each soft cap must remain visible")
            XCTAssertGreaterThan(thickness(at: cap), thickness(at: base) * 0.6,
                                 "Finish softly at useful thickness, not in a sharp point")
            XCTAssertLessThan(thickness(at: edge), thickness(at: cap) * 0.9,
                              "Round off the very end rather than cutting it square")
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
