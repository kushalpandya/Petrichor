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
            switch playlist.type {
            case .smart:
                playlistManager.showEditSmartPlaylistModal(playlist)
            case .stations:
                playlistManager.showEditStationCollectionModal(playlist)
            case .regular:
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

/// Shared by the Home radio list and a collection's contents so the two can't drift.
/// A collection lists stations it doesn't own, hence no Delete there.
enum StationMenuBuilder {
    static func items(
        for stations: [RadioStation],
        playlistManager: PlaylistManager,
        removeFrom collection: Playlist? = nil,
        onDelete: (([RadioStation]) -> Void)? = nil
    ) -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []

        if stations.count == 1, let station = stations.first {
            items.append(.button(title: String(localized: "Play"), icon: Icons.playFill) {
                AppCoordinator.shared?.playbackManager.playStation(station)
            })
            items.append(.button(title: String(localized: "Edit"), icon: Icons.edit) {
                InternetRadioManager.shared.showEditStation(station)
            })
        }

        items.append(addToCollectionItem(for: stations, playlistManager: playlistManager))

        if let collection {
            items.append(.divider)
            items.append(.button(
                title: String(localized: "Remove from Collection"),
                icon: Icons.trash,
                role: .destructive
            ) {
                Task { await playlistManager.removeStations(stations, from: collection) }
            })
        } else if let onDelete {
            items.append(.divider)
            items.append(.button(title: String(localized: "Delete"), icon: Icons.trash, role: .destructive) {
                onDelete(stations)
            })
        }

        return items
    }

    /// Mirrors `Add to Playlist` for tracks, down to the checkmark-to-remove and the
    /// absence of icons.
    private static func addToCollectionItem(
        for stations: [RadioStation],
        playlistManager: PlaylistManager
    ) -> ContextMenuItem {
        var items: [ContextMenuItem] = [
            .button(title: String(localized: "New Collection...")) {
                playlistManager.showCreateStationCollectionModal(with: stations)
            }
        ]

        let collections = playlistManager.stationCollections
        if !collections.isEmpty {
            items.append(.divider)

            let memberOf = playlistManager.collections(containing: stations)
            for collection in collections {
                let isMember = memberOf.contains(collection.id)
                items.append(.button(title: isMember ? "✓ \(collection.name)" : collection.name) {
                    Task {
                        if isMember {
                            await playlistManager.removeStations(stations, from: collection)
                        } else {
                            await playlistManager.addStations(stations, to: collection)
                        }
                    }
                })
            }
        }

        return .menu(title: String(localized: "Add to Collection"), icon: Icons.stationCollection, items: items)
    }
}
