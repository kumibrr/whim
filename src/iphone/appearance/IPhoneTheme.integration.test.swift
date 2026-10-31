#if canImport(UIKit) && WHIM_SYSTEM_SURFACE_TESTS
import SwiftUI
import XCTest
import WhimCore
import WhimIPhone
@testable import whim

@MainActor final class IPhoneSpacingTests: XCTestCase {
    func testPermissionsPageRecordsTheVisitAndRemovesTheHomeReminder() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        let suite = "permission-render-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = fixture.makeService(permissions: PermissionReviewFixture())
        try await client.completeOnboarding()
        let model = IPhoneModel(client: client, permissionReviewDefaults: defaults)
        await model.start()
        defer { model.stop() }
        XCTAssertTrue(model.offersPermissionReview)
        for size in [DynamicTypeSize.large, .accessibility3] {
            try await render("permission-review-\(size.isAccessibilitySize ? "large-text" : "standard")",
                             size: size, navigation: false, requiresScroll: false) {
                IPhoneRootView(model: model)
            }
        }
        let settings = try XCTUnwrap(model.settings)
        try await render("permissions-reviewed", size: .large) {
            SettingsSectionView(model: model, settings: settings, section: .permissions)
        }
        XCTAssertFalse(model.offersPermissionReview, "The page records its visit even without granting permission")
    }

    func testLargeDiscardTextKeepsSpaceInsideItsCapsule() {
        let label = UIHostingController(rootView: DiscardRecordingLabel()
            .environment(\.dynamicTypeSize, .accessibility3))
        let text = UIHostingController(rootView: Text("Discard").font(.body.weight(.semibold))
            .environment(\.dynamicTypeSize, .accessibility3))
        let available = CGSize(width: 335, height: 1_000)
        XCTAssertGreaterThanOrEqual(label.sizeThatFits(in: available).width - text.sizeThatFits(in: available).width, 32,
            "Enlarged text needs breathing room inside the rounded control")
    }

    func testAccessibleSettingsGiveLabelsAndValuesSeparateLines() {
        let host = UIHostingController(rootView: WhimLabeledValue {
            Text("Audio")
        } value: {
            Text("30 days")
        }.environment(\.dynamicTypeSize, .accessibility3))
        let size = host.sizeThatFits(in: CGSize(width: 335, height: 1_000))
        XCTAssertGreaterThan(size.height, 80,
            "At accessibility sizes the value needs its own line instead of squeezing the label")
    }

    // Break: a retired bottom control reservation leaves a large blank scrollable tail on every page.
    func testContentEndsWithPagePaddingRatherThanAnUnusedControlReservation() async throws {
        let host = UIHostingController(rootView: WhimContent {
            Color.white.frame(height: 1_000)
        })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let scroll = try XCTUnwrap(descendant(UIScrollView.self, in: host.view))
        XCTAssertLessThanOrEqual(scroll.contentSize.height - 1_000, 64,
            "Page padding must not reserve room for controls that no longer exist")
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width,
            "Page content must stay inside a narrow iPhone viewport")
    }

    // Break: shared page insets or fixed-width children make a page scroll horizontally.
    // Keep native renders as attachments so spacing can also be reviewed visually.
    func testScrollablePagesFitNarrowViewportsAtStandardAndAccessibilityTextSizes() async throws {
        let fixture = try WhimFacadeHarness()
        defer { fixture.remove() }
        let resources = try XCTUnwrap(Bundle(url: Bundle.main.bundleURL
            .appendingPathComponent("WhimCore_WhimCore.bundle")))
        let audio = try XCTUnwrap(resources.url(forResource: "configuration-test-fixture", withExtension: "m4a"))
        await fixture.recorder.usePreparedAudio(at: audio)
        let permissions = MutablePermissions()
        await permissions.grant()
        let client = fixture.makeService(isConnected: { false }, permissions: permissions)
        let suite = "spacing-render-\(UUID().uuidString)"
        let reviewDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { reviewDefaults.removePersistentDomain(forName: suite) }
        let model = IPhoneModel(client: client, permissionReviewDefaults: reviewDefaults)
        await model.start()
        defer { model.stop() }
        let settings = try await client.settings()
        _ = try await client.startRecording(source: .iphone)
        let stoppedNote = try await client.stopRecording()
        let note = try XCTUnwrap(stoppedNote)
        await model.refresh()

        let defaults = UserDefaults(suiteName: WhimProductionComposition.appGroupIdentifier)!
        let previousStep = defaults.object(forKey: "onboarding.v1.step")
        defaults.set(0, forKey: "onboarding.v1.step")
        defer {
            if let previousStep { defaults.set(previousStep, forKey: "onboarding.v1.step") }
            else { defaults.removeObject(forKey: "onboarding.v1.step") }
        }

        for size in [DynamicTypeSize.large, .accessibility3] {
            let suffix = size.isAccessibilitySize ? "large-text" : "standard"
            for step in 0...2 {
                defaults.set(step, forKey: "onboarding.v1.step")
                try await render("onboarding-\(step + 1)-\(suffix)", size: size) {
                    OnboardingView(model: model, settings: settings)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            try await render("settings-\(suffix)", size: size) {
                PreferencesView(model: model, settings: settings)
            }
            for section in SettingsSection.allCases {
                try await render("\(section.rawValue)-\(suffix)", size: size) {
                    SettingsSectionView(model: model, settings: settings, section: section)
                }
            }
            try await render("history-\(suffix)", size: size) {
                TimelineView(model: model, open: { _ in }).navigationTitle("Previous notes")
            }
            try await render("note-detail-\(suffix)", size: size) {
                NoteDetailView(root: model, noteID: note.id)
            }
            try await client.completeOnboarding()
            await model.refresh()
            try await render("capture-\(suffix)", size: size, navigation: false, requiresScroll: false) {
                IPhoneRootView(model: model)
            }
            await model.startRecording()
            try await render("recording-\(suffix)", size: size, navigation: false, requiresScroll: false) {
                IPhoneRootView(model: model)
            }
            await model.discardRecording()
        }
    }

    private func render<Content: View>(_ name: String, size: DynamicTypeSize,
                                      navigation: Bool = true, requiresScroll: Bool = true,
                                      @ViewBuilder content: () -> Content) async throws {
        print("Rendering spacing check: \(name)")
        let page = AnyView(content())
        let root = navigation ? AnyView(NavigationStack { page }) : page
        let host = UIHostingController(rootView: root
            .environment(\.dynamicTypeSize, size).preferredColorScheme(.dark))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousWindow?.makeKey() }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutIfNeeded()
        if requiresScroll {
            let scroll = try XCTUnwrap(descendant(UIScrollView.self, in: host.view), name)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1, name)
        }
        let picture = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true),
                "The native render must contain the visible page: \(name)")
        }
        let attachment = XCTAttachment(image: picture)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func descendant<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }
}
private actor PermissionReviewFixture: PermissionAdapter {
    func status(_ kind: PermissionKind) -> PermissionStatus { kind == .microphone ? .granted : .notDetermined }
    func request(_ kind: PermissionKind) -> PermissionStatus { status(kind) }
    func openSettings() {}
}
#endif
