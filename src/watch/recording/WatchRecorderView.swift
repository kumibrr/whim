import SwiftUI

struct WatchRecorderView: View {
    @Bindable var model: WatchModel
    @State private var confirmsDiscard = false
    var body: some View {
        VStack {
            Text("Recording").accessibilityIdentifier("watch-recorder")
            Text(Duration.seconds(model.elapsed).formatted(.time(pattern: .minuteSecond)))
                .font(.title.monospacedDigit()).accessibilityIdentifier("watch-elapsed")
            if model.warned { Text("Stopping at five minutes").accessibilityIdentifier("watch-limit-warning") }
            Button("Stop") { Task { await model.stop() } }
                .accessibilityIdentifier("watch-stop").disabled(model.busy)
            Button("Discard", role: .destructive) { confirmsDiscard = true }
                .accessibilityIdentifier("watch-discard").disabled(model.busy)
        }
        .confirmationDialog("Discard this Recording Session?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard Recording", role: .destructive) { Task { await model.discard() } }
            Button("Keep Recording", role: .cancel) {}
        }
    }
}
