import SwiftUI
import WhimCore

struct WebhookStatusView: View {
    let available: Bool
    let synchronization: WatchSettingsProjection
    var body: some View {
        VStack {
            Text(available ? "Webhook available" : "Webhook unavailable")
                .accessibilityIdentifier("watch-webhook-status")
            Text(synchronization.lastSynchronizedAt.map { "Last synchronized: " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not yet synchronized").font(.footnote)
            if synchronization.resetState == "pending" { Text("Reset pending on iPhone").font(.footnote) }
        }
    }
}
