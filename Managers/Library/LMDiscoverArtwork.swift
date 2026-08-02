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
        let pending = (featuredSection.entities + mostLovedSection.entities + recentlyPlayedSection.entities)
            .compactMap { $0 as? PlaylistEntity }
            .compactMap { playlistsById[$0.id] }
            .filter {
                discoverWarmedPlaylistSignatures[$0.id]
                    != Self.collageSignature(for: $0, smartTracks: smartTracks, smartVersions: smartVersions)
            }

        guard !pending.isEmpty else { return }

        let manager = databaseManager
        var didChange = false

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
                // The render describes superseded criteria. Drop any previous collage and
                // leave the signature unrecorded so the next pass retries.
                discoverPlaylistArtwork.removeValue(forKey: playlist.id)
                discoverWarmedPlaylistSignatures.removeValue(forKey: playlist.id)
                didChange = true
                continue
            }
            guard Self.collageSignature(
                for: live, smartTracks: smartTracks, smartVersions: smartVersions
            ) == signature else { continue }

            // Recorded even when nothing rendered, so a playlist with no usable artwork
            // isn't re-hydrated on every load.
            discoverWarmedPlaylistSignatures[playlist.id] = signature
            if let artwork {
                discoverPlaylistArtwork[playlist.id] = artwork
            } else {
                // Authoritative absence: keeping the old entry would strand a stale collage
                // behind a matching signature that stops any retry.
                discoverPlaylistArtwork.removeValue(forKey: playlist.id)
            }
            didChange = true
        }

        guard didChange, generation == discoverArtworkGeneration else { return }

        let current = currentPlaylistsById()
        featuredSection = .loaded(applyingPlaylistArtwork(to: featuredSection.entities, playlists: current))
        mostLovedSection = .loaded(applyingPlaylistArtwork(to: mostLovedSection.entities, playlists: current))
        recentlyPlayedSection = .loaded(
            applyingPlaylistArtwork(to: recentlyPlayedSection.entities, playlists: current)
        )
    }

    func currentPlaylistsById() -> [UUID: Playlist] {
        Dictionary(
            (AppCoordinator.shared?.playlistManager.playlists ?? []).map { ($0.id, $0) }
        ) { first, _ in first }
    }

    private func applyingPlaylistArtwork(
        to entities: [any Entity],
        playlists: [UUID: Playlist]
    ) -> [any Entity] {
        entities.map { entity in
            guard let playlistEntity = entity as? PlaylistEntity,
                  let playlist = playlists[playlistEntity.id] else { return entity }

            return PlaylistEntity(
                playlist: playlist,
                artworkData: discoverPlaylistArtwork[playlistEntity.id],
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
