import SwiftUI
extension Color { static let whimAccent = Color(red: 204/255, green: 73/255, blue: 57/255) }
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
