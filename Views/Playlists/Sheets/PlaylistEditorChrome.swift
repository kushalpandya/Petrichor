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
