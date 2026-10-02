import AppIntents
import SwiftUI
import WidgetKit

struct RecordWhimControl: ControlWidget {
    // Controls only render symbols, so the compact Whim mark ships as a custom symbol.
    static let symbolName = "whim.small.symbol"
    let action: RecordWhimIntent
    init() { self.action = RecordWhimIntent() }
    init(action: RecordWhimIntent) { self.action = action }
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.whim.record") {
            ControlWidgetButton(action: action) { Label("Record a Whim", image: Self.symbolName) }
        }
        .displayName("Record a Whim")
        .description("Start a voice Note in Whim.")
    }
}
