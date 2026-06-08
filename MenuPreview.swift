import SwiftUI

// Standalone preview-only mirror of the MenuBarExtra popover contents.
// Kept separate from `CleankeyApp.swift` so the production view stays untouched.

private struct PreviewHoverRow: ViewModifier {
    @State private var isHover = false
    func body(content: Content) -> some View {
        content
            .onHover { isHover = $0 }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHover ? Color.secondary.opacity(0.15) : Color.clear)
            )
    }
}

private extension View {
    func previewHoverRow() -> some View { self.modifier(PreviewHoverRow()) }
}

struct MenuPreviewBody: View {
    @State var isBlocking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Keyboard Cleaning")
                    .font(.body)

                Spacer()

                Toggle("", isOn: $isBlocking)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .fixedSize()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)

            Divider()

            VStack(spacing: 4) {
                Button("Input Monitoring Settings…") {}
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .previewHoverRow()

                Button("Accessibility Settings…") {}
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                    .previewHoverRow()
            }

            Divider()

            HStack {
                Text("v1.2v1")
                    .font(.body)

                Spacer()

                Button("Quit") {}
                    .buttonStyle(.plain)
                    .font(.body)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
        }
        .padding(8)
        .frame(width: 256)
        .background(.regularMaterial)
    }
}

#Preview("Inactive") {
    MenuPreviewBody(isBlocking: false)
        .padding(24)
        .background(Color.gray.opacity(0.2))
}

#Preview("Active") {
    MenuPreviewBody(isBlocking: true)
        .padding(24)
        .background(Color.gray.opacity(0.2))
}
