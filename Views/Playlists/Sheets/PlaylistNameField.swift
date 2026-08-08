import SwiftUI

/// Shared by the playlist, smart playlist and station editor sheets. Styled to read as
/// inline title editing rather than a labelled form field.
struct PlaylistNameField: View {
    @Binding var name: String
    var placeholder = String(localized: "Playlist Name")

    var body: some View {
        // Custom placeholder so only the typed text is bold; the placeholder stays regular
        // weight (a plain TextField would render the placeholder bold too).
        ZStack(alignment: .leading) {
            if name.isEmpty {
                Text(placeholder)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(Color(nsColor: .placeholderTextColor))
            }

            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

#Preview {
    PlaylistNameField(name: .constant("My Playlist"))
        .frame(width: 400)
}
