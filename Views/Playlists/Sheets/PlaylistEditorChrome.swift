import SwiftUI

/// Shared header and footer for the regular and smart playlist editor sheets, so their
/// identical top bar and same-skeleton bottom bar stay in sync.

struct PlaylistEditorHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: Icons.xmarkCircleFill)
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .help("Dismiss")
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
            .focusable(false)

            Text(title)
                .font(.headline)

            Spacer()
        }
        .padding()
    }
}

/// Footer with an optional left-aligned summary (change/match count) and the Cancel/Save
/// actions. `saveTitle` is "Create" or "Save" depending on the editor mode.
struct PlaylistEditorFooter: View {
    let summary: String?
    let saveTitle: String
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button(saveTitle) {
                onSave()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding()
    }
}

/// The search field shared by the playlist and station-collection editors.
struct EditorSearchField: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    var onChange: () -> Void = {}

    static let controlHeight: CGFloat = 28

    var body: some View {
        HStack {
            Image(systemName: Icons.magnifyingGlass)
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit { onChange() }
                .onChange(of: text) { onChange() }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: Icons.xmarkCircleFill)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.controlHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}
