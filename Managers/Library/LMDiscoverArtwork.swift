//
// LibraryManager class extension
//
// Playlist collage warming for the Discover carousels. Covers render lazily, so a tile
// would otherwise sit on a placeholder until something else asked for one.
//

import Foundation

extension LibraryManager {
    // MARK: - Playlist Artwork

    /// Renders 4-up collages for whichever playlist tiles ended up in the rows.
    ///
    /// A follow-up pass rather than part of building the entities: a cover needs the
    /// playlist's tracks materialized (a cold smart playlist has none) plus a CoreGraphics
    /// render, and Discover loads at launch.
    @MainActor
    func warmDiscoverPlaylistArtwork(
        smartTracks: [UUID: [Track]],
        smartVersions: [UUID: Date],
        generation: Int
    ) async {
        guard generation == discoverArtworkGeneration else { return }

        let playlistsById = currentPlaylistsById()

        // `PlaylistArtworkCache` can't shortcut this alone: a cold playlist's `artworkData`
        // keys off an empty track list, so it never matches the entry stored under the
        // hydrated key, and a playlist whose tracks carry no art caches nothing at all.
        let carouselPlaylists = featuredSection.entities
            + mostLovedSection.entities
            + recentlyPlayedSection.entities
        let pending = Dictionary(
            carouselPlaylists.compactMap { entity -> (UUID, Playlist)? in
                guard let playlistEntity = entity as? PlaylistEntity,
                      let playlist = playlistsById[playlistEntity.id],
                      discoverWarmedPlaylistSignatures[playlist.id]
                        != Self.collageSignature(
                            for: playlist,
                            smartTracks: smartTracks,
                            smartVersions: smartVersions
                        ) else { return nil }
                return (playlist.id, playlist)
            }
        ) { first, _ in first }.values

        guard !pending.isEmpty else { return }

        let manager = databaseManager
        var updates: [UUID: (signature: String, artwork: Data?)] = [:]
        var invalidatedPlaylistIds: Set<UUID> = []

        for playlist in pending {
            let signature = Self.collageSignature(
                for: playlist, smartTracks: smartTracks, smartVersions: smartVersions
            )

            // Hydration hits the database, so it runs off the main thread, reusing this
            // load's evaluation where there is one. An empty evaluation is authoritative and
            // must replace the tracks rather than fall through to a stale set.
            let hydrated = await Task.detached(priority: .utility) { () -> Playlist in
                var copy = playlist
                if let evaluated = smartTracks[playlist.id] {
                    copy.tracks = evaluated
                    return copy
                }
                guard !copy.tracks.contains(where: { $0.albumArtworkData != nil }) else { return copy }
                copy.tracks = playlist.type == .smart
                    ? manager.getTracksForSmartPlaylistSync(playlist)
                    : manager.loadTracksForPlaylist(playlist.id)
                return copy
            }.value

            let artwork = await hydrated.warmArtworkCacheIfNeeded()

            // Warming runs from two entry points, so without this an older render wins by
            // finishing last.
            guard generation == discoverArtworkGeneration else { return }
            // Re-read rather than reuse the pre-await snapshot: an edit during rendering is
            // what this catches, and the captured dictionary compared against itself can't.
            guard let live = currentPlaylistsById()[playlist.id] else { continue }
            if let evaluatedAt = smartVersions[playlist.id], live.dateModified != evaluatedAt {
                invalidatedPlaylistIds.insert(playlist.id)
                continue
            }
            guard Self.collageSignature(
                for: live, smartTracks: smartTracks, smartVersions: smartVersions
            ) == signature else {
                invalidatedPlaylistIds.insert(playlist.id)
                continue
            }

            updates[playlist.id] = (signature, artwork)
        }

        guard generation == discoverArtworkGeneration else { return }

        for playlistId in invalidatedPlaylistIds {
            discoverPlaylistArtwork.removeValue(forKey: playlistId)
            discoverWarmedPlaylistSignatures.removeValue(forKey: playlistId)
        }
        for (playlistId, update) in updates {
            discoverWarmedPlaylistSignatures[playlistId] = update.signature
            discoverPlaylistArtwork[playlistId] = update.artwork
        }

        let changedPlaylistIds = invalidatedPlaylistIds.union(updates.keys)
        guard !changedPlaylistIds.isEmpty else { return }

        let current = currentPlaylistsById()
        if let updated = applyingPlaylistArtwork(
            to: featuredSection.entities,
            playlists: current,
            changedPlaylistIds: changedPlaylistIds
        ) {
            featuredSection = .loaded(updated)
        }
        if let updated = applyingPlaylistArtwork(
            to: mostLovedSection.entities,
            playlists: current,
            changedPlaylistIds: changedPlaylistIds
        ) {
            mostLovedSection = .loaded(updated)
        }
        if let updated = applyingPlaylistArtwork(
            to: recentlyPlayedSection.entities,
            playlists: current,
            changedPlaylistIds: changedPlaylistIds
        ) {
            recentlyPlayedSection = .loaded(updated)
        }
    }

    func currentPlaylistsById() -> [UUID: Playlist] {
        Dictionary(
            (AppCoordinator.shared?.playlistManager.playlists ?? []).map { ($0.id, $0) }
        ) { first, _ in first }
    }

    private func applyingPlaylistArtwork(
        to entities: [any Entity],
        playlists: [UUID: Playlist],
        changedPlaylistIds: Set<UUID>
    ) -> [any Entity]? {
        guard entities.contains(where: { changedPlaylistIds.contains($0.id) }) else { return nil }

        return entities.map { entity in
            guard let playlistEntity = entity as? PlaylistEntity,
                  changedPlaylistIds.contains(playlistEntity.id),
                  let playlist = playlists[playlistEntity.id] else { return entity }

            return PlaylistEntity(
                playlist: playlist,
                artworkData: discoverPlaylistArtwork[playlistEntity.id] ?? playlist.artworkData,
                trackCount: playlistEntity.trackCount
            )
        }
    }

    /// Decides whether a cached collage is current.
    ///
    /// `Playlist.artworkSignature` can't see an auto-updating smart playlist's membership:
    /// `tracks` is empty while cold, and a background re-evaluation refreshes `trackCount`
    /// without touching `dateModified`, so a same-size swap looks unchanged.
    private static func collageSignature(
        for playlist: Playlist,
        smartTracks: [UUID: [Track]],
        smartVersions: [UUID: Date]
    ) -> String {
        guard playlist.needsInMemorySmartEvaluation, let evaluated = smartTracks[playlist.id] else {
            return playlist.artworkSignature
        }
        // The version the membership was evaluated against, not the current one: a stale
        // digest paired with a fresh date makes both sides of the post-render check agree
        // while describing artwork that no longer matches the criteria.
        let evaluatedAt = smartVersions[playlist.id] ?? playlist.dateModified
        let digest = Playlist.membershipDigest(of: evaluated.compactMap(\.trackId))
        return "\(playlist.id)-smart-\(evaluated.count)-\(digest)-\(evaluatedAt.timeIntervalSince1970)"
    }
}
