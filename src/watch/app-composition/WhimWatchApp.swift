import SwiftUI

enum WhimWatchRoot {
    static let accessibilityIdentifier = "watch-root"
}

@main
struct WhimWatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Whim")
                .accessibilityIdentifier(WhimWatchRoot.accessibilityIdentifier)
        }
    }
}
