import AppIntents
import SwiftUI
import WidgetKit

struct RecordWhimControl: ControlWidget {
    let action: RecordWhimIntent
    init() { self.action = RecordWhimIntent() }
    init(action: RecordWhimIntent) { self.action = action }
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.whim.record") {
            ControlWidgetButton(action: action) { Label("Record a Whim", systemImage: "mic.fill") }
        }
        .displayName("Record a Whim")
        .description("Start a voice Note in Whim.")
    }
}
