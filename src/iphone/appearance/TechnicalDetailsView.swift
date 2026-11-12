import SwiftUI
import WhimIPhone

struct TechnicalDetailsView<Content: View>: View {
    let rows: [SynchronizationTechnicalRow]
    let identifier: String
    @ViewBuilder var content: Content
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.label).font(.caption).foregroundStyle(.secondary)
                        Text(row.value).font(.callout).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                content
            }.padding(.vertical, 12)
        } label: {
            Text("Technical details").frame(minHeight: 44)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
