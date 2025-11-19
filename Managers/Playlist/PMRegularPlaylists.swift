//
// PlaylistManager class extension
//
// This extension contains methods for doing CRUD operations on regular playlists,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation

extension PlaylistManager {
    func showCreatePlaylistModal(with tracks: [Track] = []) {
        tracksToAddToNewPlaylist = tracks
        newPlaylistName = ""
        showingCreatePlaylistModal = true
    }
    
    func createPlaylistFromModal() {
        guard !newPlaylistName.isEmpty else { return }
        
        _ = createPlaylist(name: newPlaylistName, tracks: tracksToAddToNewPlaylist)
        
        // Reset modal state
        newPlaylistName = ""
        tracksToAddToNewPlaylist = []
        showingCreatePlaylistModal = false
    }
    
    func cancelCreatePlaylistModal() {
        newPlaylistName = ""
        tracksToAddToNewPlaylist = []
        showingCreatePlaylistModal = false
    }
    
    /// Create a new basic playlist
    func createPlaylist(name: String, tracks: [Track] = []) -> Playlist {
        var newPlaylist = Playlist(name: name, tracks: tracks)
        newPlaylist.trackCount = tracks.count
        playlists.append(newPlaylist)
        
        // Save to database
        Task {
            do {
                if let dbManager = libraryManager?.databaseManager {
                    try await dbManager.savePlaylistAsync(newPlaylist)
                }
            } catch {
                Logger.error("Failed to save new playlist: \(error)")
            }
        }
        
        return newPlaylist
    }
    
    /// Delete a playlist
    func deletePlaylist(_ playlist: Playlist) {
        // Only allow deletion of user-editable playlists
        guard playlist.isUserEditable else {
            Logger.warning("Cannot delete system playlist: \(playlist.name)")
            return
        }
        
        // Remove from memory
        playlists.removeAll { $0.id == playlist.id }
        
        // Remove from database
        Task {
            do {
                // Remove the playlist from pinned items if needed
                await handlePlaylistDeletionForPinnedItems(playlist.id)
                
                // Remove the playlist from db
                if let dbManager = libraryManager?.databaseManager {
                    try await dbManager.deletePlaylist(playlist.id)
                }
            } catch {
                Logger.error("Failed to delete playlist from database: \(error)")
            }
        }
    }
    
    /// Rename a playlist
    func renamePlaylist(_ playlist: Playlist, newName: String) {
        guard playlist.isUserEditable else {
            Logger.warning("Cannot rename system playlist: \(playlist.name)")
            return
        }
        
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            var updatedPlaylist = playlists[index]
            updatedPlaylist.name = newName
            updatedPlaylist.dateModified = Date()
            playlists[index] = updatedPlaylist
            
            // Save to database
            Task {
                do {
                    if let dbManager = libraryManager?.databaseManager {
                        try await dbManager.savePlaylistAsync(updatedPlaylist)
                    }
                } catch {
                    Logger.error("Failed to save renamed playlist: \(error)")
                }
            }
        }
    }
    
    internal func addTrackToRegularPlaylist(track: Track, playlistID: UUID) async {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].type == .regular,
              playlists[index].isContentEditable else {
            Logger.warning("Cannot add to this playlist")
            return
        }

        // Check if track already exists
        let alreadyExists = await MainActor.run {
            self.playlists[index].tracks.contains { $0.trackId == track.trackId }
        }
        
        if alreadyExists {
            Logger.info("Track already in playlist")
            return
        }

        // Add track on main thread
        await MainActor.run {
            self.playlists[index].addTrack(track)
        }

        // Save to database - use efficient single track method
        if let dbManager = libraryManager?.databaseManager {
            let success = await dbManager.addTrackToPlaylist(playlistId: playlistID, track: track)
            if !success {
                // Revert change on main thread
                await MainActor.run {
                    self.playlists[index].removeTrack(track)
                }
            }
        }
    }
    
    internal func removeTrackFromRegularPlaylist(track: Track, playlistID: UUID) async {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].type == .regular,
              playlists[index].isContentEditable else {
            Logger.warning("Cannot remove from this playlist")
            return
        }

        // Perform the track removal on main thread
        await MainActor.run {
            self.playlists[index].removeTrack(track)
            self.playlists[index].trackCount = self.playlists[index].tracks.count
        }

        // Save to database
        do {
            if let dbManager = libraryManager?.databaseManager {
                // Get the updated playlist from main thread
                let updatedPlaylist = await MainActor.run { self.playlists[index] }
                try await dbManager.savePlaylistAsync(updatedPlaylist)
            }
        } catch {
            Logger.error("Failed to save playlist: \(error)")
            await MainActor.run {
                self.playlists[index].addTrack(track)
                self.playlists[index].trackCount = self.playlists[index].tracks.count
            }
        }
    }
    
    /// Add multiple tracks to a playlist
    func addTracksToPlaylist(tracks: [Track], playlistID: UUID) async {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].type == .regular,
              playlists[index].isContentEditable else {
            Logger.warning("Cannot add tracks to this playlist")
            return
        }
        
        await MainActor.run {
            let existingTrackIds = Set(self.playlists[index].tracks.compactMap { $0.trackId })
            let newTracks = tracks.filter { track in
                guard let trackId = track.trackId else { return false }
                return !existingTrackIds.contains(trackId)
            }
            
            // Batch append all new tracks
            self.playlists[index].tracks.append(contentsOf: newTracks)
            
            // Update metadata
            self.playlists[index].dateModified = Date()
            self.playlists[index].trackCount = self.playlists[index].tracks.count
            
            Logger.info("Added \(newTracks.count) tracks to playlist '\(self.playlists[index].name)'")
        }
        
        let updatedPlaylist = await MainActor.run { self.playlists[index] }
        do {
            if let dbManager = libraryManager?.databaseManager {
                try await dbManager.savePlaylistAsync(updatedPlaylist)
                Logger.info("Saved playlist with \(updatedPlaylist.trackCount) tracks to database")
            }
        } catch {
            Logger.error("Failed to save playlist after adding tracks: \(error)")
        }
    }
    
    /// Remove multiple tracks from a playlist efficiently
    func removeTracksFromPlaylist(tracks: [Track], playlistID: UUID) async {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].type == .regular,
              playlists[index].isContentEditable else {
            Logger.warning("Cannot remove tracks from this playlist")
            return
        }
        
        // Update the playlist on main thread
        await MainActor.run {
            // Create a Set of track IDs to remove for efficient lookup
            let trackIdsToRemove = Set(tracks.compactMap { $0.trackId })
            
            // Remove all matching tracks in one go
            self.playlists[index].tracks.removeAll { track in
                guard let trackId = track.trackId else { return false }
                return trackIdsToRemove.contains(trackId)
            }
            
            // Update metadata
            self.playlists[index].dateModified = Date()
            self.playlists[index].trackCount = self.playlists[index].tracks.count
            
            Logger.info("Removed \(tracks.count) tracks from playlist '\(self.playlists[index].name)'")
        }
        
        // Save to database in background (single write)
        let updatedPlaylist = await MainActor.run { self.playlists[index] }
        do {
            if let dbManager = libraryManager?.databaseManager {
                try await dbManager.savePlaylistAsync(updatedPlaylist)
                Logger.info("Saved playlist with \(updatedPlaylist.trackCount) tracks to database")
            }
        } catch {
            Logger.error("Failed to save playlist after removing tracks: \(error)")
        }
    }
    
    /// Refresh playlists after a folder is removed from the library
    func refreshPlaylistsAfterFolderRemoval() {
        // Remove tracks that no longer exist from regular playlists
        for index in playlists.indices {
            if playlists[index].type == .regular {
                let validTracks = playlists[index].tracks.filter { track in
                    // Check if track still exists in library
                    libraryManager?.tracks.contains { $0.trackId == track.trackId } ?? false
                }
                
                if validTracks.count < playlists[index].tracks.count {
                    playlists[index].tracks = validTracks
                    playlists[index].dateModified = Date()
                    
                    // Save updated playlist
                    Task {
                        do {
                            if let dbManager = libraryManager?.databaseManager {
                                try await dbManager.savePlaylistAsync(playlists[index])
                            }
                        } catch {
                            Logger.error("Failed to update playlist after folder removal: \(error)")
                        }
                    }
                }
            }
        }
        
        // Update smart playlists
        updateSmartPlaylists()
    }
}
