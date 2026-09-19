import SwiftUI
import WhimCore
import WhimIPhone
struct PendingIPhoneLink { let id = UUID(); let url: URL }
@main struct WhimIPhoneApp: App {
    @State private var model: IPhoneModel?
    @State private var failure: String?
    @State private var starting = false
    @State private var pendingLink: PendingIPhoneLink?
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { IPhoneRootView(model: model, pendingLink: pendingLink) }
                else {
                    VStack(spacing: 20) {
                        Text(failure ?? "Loading Whim…")
                        if failure != nil { Button("Refresh") { Task { await launch() } } }
                    }.task { await launch() }
                }
            }.tint(.primary).buttonStyle(WhimButtonStyle())
                .onOpenURL { pendingLink = PendingIPhoneLink(url: $0) }
        }
    }
    @MainActor private func launch() async {
        guard !starting, model == nil else { return }; starting = true
        defer { starting = false }
        do { model = IPhoneModel(client: try await WhimProductionComposition.make()) }
        catch { failure = IPhoneError(error).message }
    }
}
