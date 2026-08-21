import SwiftUI

struct ArtworkInputField: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    let leadingIcon: String
    let actionIcon: String
    let actionHelp: LocalizedStringKey
    let isActionEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SymbolImage(leadingIcon)
                .foregroundColor(.secondary)
                .frame(width: 16)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit(action)

            ZStack {
                Button(action: action) {
                    SymbolImage(actionIcon)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isActionEnabled || isLoading)
                .opacity(isLoading ? 0 : 1)
                .help(actionHelp)

                ProgressView()
                    .controlSize(.small)
                    .opacity(isLoading ? 1 : 0)
                    .accessibilityHidden(!isLoading)
            }
            .frame(width: 18, height: 18)
        }
        .padding(.horizontal, 8)
        .frame(height: EditorSearchField.controlHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}
