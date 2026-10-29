import AppIntents
import SwiftUI
import UIKit
import WhimCore
import XCTest

@MainActor final class WhimLiveActivityTests: XCTestCase {
    // Break: the Stop circle becomes opaque, disappears, or moves off-center.
    func testExpandedIslandShowsRedStopInTranslucentCircleAtItsCenter() throws {
        let view = RecordingIslandExpandedView(
            state: .init(startedAt: Date(), power: -160, tone: 0))
        let renderer = ImageRenderer(content: view.frame(width: 280, height: 104).background(.blue))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var redPixels = 0
        for y in (image.height / 2 - 6)..<(image.height / 2 + 6) {
            for x in (image.width / 2 - 6)..<(image.width / 2 + 6) {
                let offset = (y * image.width + x) * 4
                if pixels[offset] > 200 && pixels[offset + 1] < 100 && pixels[offset + 2] < 100 {
                    redPixels += 1
                }
            }
        }
        XCTAssertEqual(redPixels, 144, "Stop must be visibly red in the center")
        let circle = ((image.height / 2 - 28) * image.width + image.width / 2) * 4
        XCTAssertGreaterThan(pixels[circle], 16, "The circular surround must remain visible")
        XCTAssertGreaterThan(pixels[circle + 2], 180, "The background must show through the Stop circle")
        let outsideCircle = ((image.height / 2 - 34) * image.width + image.width / 2 + 34) * 4
        XCTAssertLessThan(pixels[outsideCircle], 8, "The surround must be circular, not a square")
    }

    // Break: widget snapshots rely on onAppear/@State and render the idle logo for every measurement.
    func testEveryIslandSizeRendersMeasuredVoiceWithoutLifecycleCallbacks() throws {
        for size in [CGSize(width: 280, height: 80), CGSize(width: 32, height: 24), CGSize(width: 22, height: 22)] {
            let quiet = try waveform(power: -160, tone: 0, size: size)
            let speech = try waveform(power: -6, tone: 0.1, size: size)
            let bright = try waveform(power: -6, tone: 0.9, size: size)
            XCTAssertNotEqual(quiet, speech, "Voice amplitude must change the rendered waveform at \(size)")
            XCTAssertNotEqual(speech, bright, "Voice tone must change the rendered waveform at \(size)")
        }
    }

    // Break: the expanded waveform's action opens Whim or fails to finalize the app's Recording Session.
    func testExpandedWaveformStopsAndSavesTheRecordingOnce() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        let permissions = MutablePermissions()
        await permissions.grant()
        let client = fixture.makeService(permissions: permissions)
        let runtime = WhimRuntime(make: { client })
        let session = try await client.startRecording(source: .iphone)
        let view = RecordingIslandExpandedView(
            state: .init(startedAt: session.createdAt, power: -12, tone: 0.7),
            stopIntent: StopWhimRecordingIntent(runtime: runtime))
        _ = try await view.stopIntent.perform()
        _ = try await view.stopIntent.perform()
        let active = try await client.activeRecording()
        let notes = try await client.listNotes(filter: .all)
        XCTAssertNil(active)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.id.rawValue.uuidString.lowercased(), session.noteID)
    }

    private func waveform(power: Double, tone: Double, size: CGSize) throws -> Data {
        let renderer = ImageRenderer(content: LiveWaveformSnapshotView(power: power, tone: tone)
            .frame(width: size.width, height: size.height))
        renderer.scale = 3
        return try XCTUnwrap(renderer.uiImage?.pngData())
    }
}
