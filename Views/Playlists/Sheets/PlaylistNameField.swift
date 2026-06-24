import SwiftUI

/// Large, borderless playlist-name field shared by the regular and smart playlist editor
/// sheets. Styled to read like inline title editing rather than a labelled form field.
struct PlaylistNameField: View {
    @Binding var name: String

    var body: some View {
        // Custom placeholder so only the typed text is bold; the placeholder stays regular
        // weight (a plain TextField would render the placeholder bold too).
        ZStack(alignment: .leading) {
            if name.isEmpty {
                Text("Playlist Name")
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
