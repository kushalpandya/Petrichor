import SwiftUI

/// Single source of truth for a playlist's options menu (Pin, Edit, Delete), so the Playlist
/// sidebar and the Home sidebar (for pinned playlists) present the exact same menu. Editing
/// (including renaming) happens through the editor sheet, so there's no inline-rename action.
enum PlaylistMenuBuilder {
    static func items(
        for playlist: Playlist,
        playlistManager: PlaylistManager,
        onDelete: @escaping () -> Void
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = [playlistManager.createPinContextMenuItem(for: playlist)]

        guard playlist.isUserEditable else { return items }

        items.append(.divider)

        // "Edit" opens the editor sheet for both kinds (rules for smart, contents for regular);
        // the label is kept identical for consistency.
        items.append(.button(title: String(localized: "Edit")) {
            if playlist.type == .smart {
                playlistManager.showEditSmartPlaylistModal(playlist)
            } else {
                playlistManager.showEditRegularPlaylistModal(playlist)
            }
        })

        items.append(.divider)

        items.append(.button(title: String(localized: "Delete"), role: .destructive) {
            onDelete()
        })

        return items
    }
}
