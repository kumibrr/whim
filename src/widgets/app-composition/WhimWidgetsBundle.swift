import SwiftUI
import WidgetKit

@main struct WhimWidgetsBundle: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        WhimLiveActivity()
        RecordWhimControl()
        #else
        WhimComplication()
        #endif
    }
}
