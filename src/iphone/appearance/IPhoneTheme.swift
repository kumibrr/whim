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
