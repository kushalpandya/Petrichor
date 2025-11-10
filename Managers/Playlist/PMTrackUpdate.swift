//
// PlaylistManager class extension
//
// This extension contains methods for updating individual tracks based on user
// interaction events like marking as favorite, play count, last played, etc.
// The methods internally also use DatabaseManager methods to work with database.
//

import Foundation
import GRDB

extension PlaylistManager {
    func updateTrackFavoriteStatus(track: Track, isFavorite: Bool) async {
        guard let trackId = track.trackId else {
            Logger.error("Cannot update favorite - track has no database ID")
            return
        }

        let updatedTrack = track.withFavoriteStatus(isFavorite)

        do {
            if let dbManager = libraryManager?.databaseManager {
                try await dbManager.updateTrackFavoriteStatus(trackId: trackId, isFavorite: isFavorite)

                Logger.info("Updated favorite status for track: \(track.title) to \(isFavorite)")
                
                await handleTrackPropertyUpdate(updatedTrack)
                
                if let favoritesIndex = playlists.firstIndex(where: {
                    $0.name == DefaultPlaylists.favorites && $0.type == .smart
                }) {
                    Task.detached(priority: .background) { [weak self] in
                        guard let self = self else { return }
                        await self.loadSmartPlaylistTracks(self.playlists[favoritesIndex])
                    }
                }
            }
        } catch {
            Logger.error("Failed to update favorite status: \(error)")
        }
    }

    /// Add or remove a track from any playlist (handles both regular and smart playlists)
    func updateTrackInPlaylist(track: Track, playlist: Playlist, add: Bool) {
        Task {
            do {
                guard libraryManager?.databaseManager != nil else { return }

                // Handle smart playlists differently
                if playlist.type == .smart {
                    // For smart playlists, we update the track property that controls membership
                    if playlist.name == DefaultPlaylists.favorites && !playlist.isUserEditable {
                        // Update favorite status
                        await updateTrackFavoriteStatus(track: track, isFavorite: add)
                    }
                    // Other smart playlists are read-only
                    return
                }

                // For regular playlists, add/remove from playlist
                if add {
                    await addTrackToRegularPlaylist(track: track, playlistID: playlist.id)
                } else {
                    await removeTrackFromRegularPlaylist(track: track, playlistID: playlist.id)
                }
            }
        }
    }

    /// Update play count for a track
    func incrementPlayCount(for track: Track) {
        Task {
            guard let trackId = track.trackId else {
                Logger.error("Cannot update play count - track has no database ID")
                return
            }

            let newPlayCount = track.playCount + 1
            let lastPlayedDate = Date()

            do {
                if let dbManager = libraryManager?.databaseManager {
                    try await dbManager.updateTrackPlayInfo(
                        trackId: trackId,
                        playCount: newPlayCount,
                        lastPlayedDate: lastPlayedDate
                    )

                    let updatedTrack = track.withPlayStats(playCount: newPlayCount, lastPlayedDate: lastPlayedDate)

                    Logger.info("Incremented play count for track: \(track.title)")

                    await handleTrackPropertyUpdate(updatedTrack)
                    
                    updateSmartPlaylistCounts()
                }
            } catch {
                Logger.error("Failed to update play count: \(error)")
            }
        }
    }

    /// Handle track property updates to refresh smart playlists and other dependent data
    internal func handleTrackPropertyUpdate(_ track: Track) async {
        // Update current queue if the track is in it
        await MainActor.run {
            if let queueIndex = self.currentQueue.firstIndex(where: { $0.trackId == track.trackId }) {
                self.currentQueue[queueIndex] = track
            }
        }

        // Update current track if it's the one being updated
        if let currentTrack = audioPlayer?.currentTrack, currentTrack.trackId == track.trackId {
            await MainActor.run {
                self.audioPlayer?.currentTrack = track
            }
        }
    }

    /// Handle the start of track playback
    func handleTrackPlaybackStarted(_ track: Track) {
        Task {
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TrackPlaybackStarted"),
                    object: nil,
                    userInfo: ["track": track]
                )
            }
        }
    }

    /// Handle track playback completion
    func handleTrackPlaybackCompleted(_ track: Track) {
        // Increment play count when track completes
        incrementPlayCount(for: track)
    }
}
