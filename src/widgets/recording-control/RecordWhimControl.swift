import AppIntents
import SwiftUI
import WidgetKit

struct RecordWhimControl: ControlWidget {
    // Controls drop custom symbols, so use the system voice-recorder glyph.
    static let symbolName = "waveform"
    let action: RecordWhimIntent
    init() { self.action = RecordWhimIntent() }
    init(action: RecordWhimIntent) { self.action = action }
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.whim.record") {
            ControlWidgetButton(action: action) { Label("Record a Whim", systemImage: Self.symbolName) }
        }
        .displayName("Record a Whim")
        .description("Start a voice Note in Whim.")
    }
}
