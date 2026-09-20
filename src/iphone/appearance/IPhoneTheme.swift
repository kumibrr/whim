import SwiftUI
extension Color { static let whimAccent = Color.white }
struct WhimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body).padding(.vertical, 14).padding(.horizontal, 16).frame(minHeight: 48)
            .background(Color(uiColor: .secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 14)).opacity(configuration.isPressed ? 0.65 : 1)
    }
}
struct WhimContent<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) { content }.frame(maxWidth: .infinity, alignment: .leading).padding(24).padding(.bottom, 86) }
            .scrollDismissesKeyboard(.interactively).background(Color(uiColor: .systemBackground))
    }
}
extension View {
    func whimTitle() -> some View { font(.largeTitle.bold()).accessibilityAddTraits(.isHeader) }
    func whimHeading() -> some View { font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader) }
    func whimInput(_ label: String) -> some View {
        font(.body).padding(12).frame(minHeight: 48).overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary)).accessibilityLabel(label)
    }
}

struct WhimErrorText: View {
    let message: String
    var body: some View {
        Text(message).foregroundStyle(.red)
            .onChange(of: message, initial: true) { _, value in
                UIAccessibility.post(notification: .announcement, argument: value)
            }
    }
}

struct WhimGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(white: 0.12), in: shape)
                .overlay(shape.stroke(.white.opacity(0.25), lineWidth: 0.5))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.22), lineWidth: 0.5))
        }
    }
}
extension View {
    func whimGlass<S: Shape>(in shape: S) -> some View { modifier(WhimGlass(shape: shape)) }
}

// Keep the container above the idle/recording branches so their glass can morph.
struct CaptureGlassContainer<Content: View>: View {
    let isRecording: Bool
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) { content }
                .animation(reduceMotion || reduceTransparency ? nil : .smooth(duration: 0.35),
                           value: isRecording)
        } else {
            content
        }
    }
}

private struct CaptureGlassIdentity: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffectID(id, in: namespace)
                .glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)
        } else {
            content
        }
    }
}

extension View {
    func captureGlassIdentity(_ id: String, in namespace: Namespace.ID) -> some View {
        modifier(CaptureGlassIdentity(id: id, namespace: namespace))
    }
}

/// Error content occupies the upper safe area; the recorder retains the remaining space.
struct WhimErrorContainer: View {
    let message: String
    let actionLabel: String
    var busy = false
    let action: () -> Void
    var dismiss: (() -> Void)? = nil
    var collapse: (() -> Void)? = nil
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(message)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if busy { ProgressView() }
                else { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(RoundedRectangle(cornerRadius: 18))
            .whimGlass(in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(message)
        .accessibilityHint(actionLabel)
        .accessibilityValue(busy ? "Working" : "")
        .accessibilityIdentifier("startup-error")
        .accessibilityActions {
            if let dismiss { Button("Dismiss error", action: dismiss) }
            if let collapse { Button("Collapse notifications", action: collapse) }
        }
        .highPriorityGesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.height < -40, abs(value.translation.height) > abs(value.translation.width) {
                collapse?()
            } else if !busy, abs(value.translation.width) > 60, abs(value.translation.width) > abs(value.translation.height) * 2 {
                dismiss?()
            }
        })
    }
}

struct IPhoneStartupShell: View {
    let onboardingCompleted: Bool
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if onboardingCompleted {
                Rectangle().fill(.white).frame(height: 1).padding(.horizontal, 24)
                VStack { Spacer(); ProgressView("Preparing recording…").padding(.bottom, 48) }
            } else {
                WhimContent {
                    Text("A place for your thoughts").whimTitle()
                    Text("Whim stores voice Notes locally on your iPhone and Apple Watch and delivers them directly to your webhook. No account, cloud storage, or analytics.")
                    ProgressView("Preparing Whim…")
                }
            }
        }.accessibilityIdentifier(onboardingCompleted ? "whim-home" : "onboarding")
    }
}
