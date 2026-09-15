import SwiftUI

struct WebhookStatusView: View {
    let available: Bool
    var body: some View {
        VStack {
            Text(available ? "Webhook available" : "Webhook unavailable")
                .accessibilityIdentifier("watch-webhook-status")
            Text("Last synchronized: unavailable").font(.footnote)
        }
    }
}
