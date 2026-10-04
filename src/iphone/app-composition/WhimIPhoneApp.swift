import SwiftUI
import WhimCore
import WhimIPhone
struct PendingIPhoneLink { let id = UUID(); let url: URL }
@main struct WhimIPhoneApp: App {
    init() { BGTaskSchedulerAdapter.register() }
    @State private var model: IPhoneModel?
    @State private var failure: ActionableFailure?
    @State private var showsStorageInstructions = false
    private let onboarding = UserDefaultsOnboardingStore()
    @State private var starting = false
    @State private var pendingLink: PendingIPhoneLink?
    var body: some Scene {
        WindowGroup {
            Group {
                if let model { IPhoneRootView(model: model, pendingLink: pendingLink) }
                else {
                    IPhoneStartupShell(onboardingCompleted: onboarding.isComplete())
                        .safeAreaInset(edge: .top) {
                            if let failure {
                                WhimErrorContainer(message: failure.message, actionLabel: failure.actionLabel, busy: starting) {
                                    if failure.action == .storageInstructions { showsStorageInstructions = true }
                                    else { Task { await launch() } }
                                }.padding()
                            }
                        }.task { await launch() }
                        .alert("Free up storage", isPresented: $showsStorageInstructions) {
                            Button("Check again") { Task { await launch() } }
                            Button("Close", role: .cancel) {}
                        } message: { Text("Open iPhone Settings > General > iPhone Storage and remove items you no longer need. Then return to Whim and check again.") }
                }
            }.preferredColorScheme(.dark).tint(.white).buttonStyle(WhimButtonStyle())
                .toggleStyle(.switch(tint: Color(uiColor: .systemGreen)))
                .onOpenURL { pendingLink = PendingIPhoneLink(url: $0) }
        }
    }
    @MainActor private func launch() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        #endif
        guard !starting, model == nil else { return }; starting = true
        defer { starting = false }
        do {
            model = IPhoneModel(client: try await WhimRuntime.shared.service(), onboardingCompletedHint: onboarding.isComplete())
            failure = nil
        } catch { failure = ActionableFailure(error, operation: .preparation) }
    }
}
