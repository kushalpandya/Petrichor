//
// PlaylistManager class extension
//
// This extension contains methods for doing CRUD operations on regular playlists,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation

extension PlaylistManager {
    // MARK: - Editor Presentation

    /// Present the name-only dialog (used by the track context menu's "New Playlist...").
    func showCreatePlaylistModal(with tracks: [Track] = []) {
        tracksToAddToNewPlaylist = tracks
        newPlaylistName = ""
        showingCreatePlaylistModal = true
    }

    /// Present the unified editor (name + song selection) to create a new playlist.
    func showCreateRegularPlaylistModal() {
        regularPlaylistToEdit = nil
        showingRegularPlaylistEditor = true
    }

    /// Present the unified editor pre-filled to edit an existing regular playlist.
    func showEditRegularPlaylistModal(_ playlist: Playlist) {
        guard playlist.type == .regular, playlist.isUserEditable else { return }
        regularPlaylistToEdit = playlist
        showingRegularPlaylistEditor = true
    }

    // MARK: - Create

    /// Create a new playlist with an optional set of tracks and navigate to it. Shared by
    /// both creation flows (the name-only dialog and the unified editor) so they stay in sync.
    @discardableResult
    func createRegularPlaylist(name: String, tracks: [Track] = []) -> Playlist {
        let newPlaylist = createPlaylist(name: name, tracks: tracks)

        NotificationCenter.default.post(
            name: .navigateToPlaylists,
            object: nil,
            userInfo: ["playlistID": newPlaylist.id]
        )

        return newPlaylist
    }

    func createPlaylistFromModal() {
        guard !newPlaylistName.isEmpty else { return }

        createRegularPlaylist(name: newPlaylistName, tracks: tracksToAddToNewPlaylist)

        // Reset modal state
        newPlaylistName = ""
        tracksToAddToNewPlaylist = []
        showingCreatePlaylistModal = false
    }

    /// Create a new basic playlist
    func createPlaylist(name: String, tracks: [Track] = []) -> Playlist {
        let newPlaylist = Playlist(name: name, tracks: [])
        playlists.append(newPlaylist)

        // Save to database and add tracks
        Task {
            do {
                if let dbManager = libraryManager?.databaseManager {
                    try await dbManager.savePlaylistAsync(newPlaylist)
                }
            } catch {
                Logger.error("Failed to save new playlist: \(error)")
            }

            if !tracks.isEmpty {
                await addTracksToPlaylist(tracks: tracks, playlistID: newPlaylist.id)
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
                        try await dbManager.updatePlaylistMetadata(updatedPlaylist)

                        if let pinnedIndex = libraryManager?.pinnedItems.firstIndex(where: {
                            $0.itemType == .playlist && $0.playlistId == playlist.id
                        }) {
                            await MainActor.run {
                                libraryManager?.pinnedItems[pinnedIndex].displayName = newName
                            }
                        }
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

        await MainActor.run {
            if self.playlists[index].tracks.isEmpty, let dbManager = libraryManager?.databaseManager {
                self.playlists[index].tracks = dbManager.loadTracksForPlaylist(playlistID)
            }
        }

        // Check if track already exists
        let alreadyExists = await MainActor.run {
            self.playlists[index].tracks.contains { $0.trackId == track.trackId }
        }
        
        if alreadyExists {
            Logger.info("Track already in playlist")
            return
        }

        // Add track on main thread with playlist-specific dateAdded
        await MainActor.run {
            var playlistTrack = track
            playlistTrack.dateAdded = Date()
            self.playlists[index].addTrack(playlistTrack)
            self.playlists[index].trackCount = self.playlists[index].tracks.count
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
              playlists[index].isContentEditable,
              let dbManager = libraryManager?.databaseManager,
              let trackId = track.trackId else {
            Logger.warning("Cannot remove from this playlist")
            return
        }

        // Perform the track removal on main thread
        await MainActor.run {
            self.playlists[index].removeTrack(track)
            self.playlists[index].trackCount = self.playlists[index].tracks.count
        }

        // Save to database (incremental delete + renumber)
        do {
            try await dbManager.removeTracksFromPlaylist(playlistId: playlistID, trackIds: [trackId])
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

        guard let dbManager = libraryManager?.databaseManager else { return }

        do {
            // Incremental append (never deletes), so this is correct even if the in-memory
            // track list isn't fully loaded.
            let inserted = try await dbManager.appendTracksToPlaylist(playlistId: playlistID, tracks: tracks)

            await MainActor.run {
                guard let index = self.playlists.firstIndex(where: { $0.id == playlistID }) else { return }

                if self.playlists[index].tracks.isEmpty {
                    // Cold playlist: tracks reload lazily on view; keep the count accurate.
                    self.playlists[index].trackCount += inserted
                } else {
                    let existingTrackIds = Set(self.playlists[index].tracks.compactMap { $0.trackId })
                    let now = Date()
                    let newTracks = tracks
                        .filter { track in track.trackId.map { !existingTrackIds.contains($0) } ?? false }
                        .map { track -> Track in
                            var copy = track
                            copy.dateAdded = now
                            return copy
                        }
                    self.playlists[index].tracks.append(contentsOf: newTracks)
                    self.playlists[index].trackCount = self.playlists[index].tracks.count
                }

                self.playlists[index].dateModified = Date()
                Logger.info("Added \(inserted) tracks to playlist '\(self.playlists[index].name)'")
            }
        } catch {
            Logger.error("Failed to add tracks to playlist: \(error)")
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

        guard let dbManager = libraryManager?.databaseManager else { return }
        let trackIdsToRemove = tracks.compactMap { $0.trackId }

        do {
            // Incremental delete + renumber instead of rewriting the whole association set.
            try await dbManager.removeTracksFromPlaylist(playlistId: playlistID, trackIds: trackIdsToRemove)

            await MainActor.run {
                guard let index = self.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
                let idSet = Set(trackIdsToRemove)

                if self.playlists[index].tracks.isEmpty {
                    // Cold playlist: keep the count accurate; tracks reload lazily on view.
                    self.playlists[index].trackCount = max(0, self.playlists[index].trackCount - idSet.count)
                } else {
                    self.playlists[index].tracks.removeAll { track in
                        track.trackId.map { idSet.contains($0) } ?? false
                    }
                    self.playlists[index].trackCount = self.playlists[index].tracks.count
                }

                self.playlists[index].dateModified = Date()
                Logger.info("Removed \(idSet.count) tracks from playlist '\(self.playlists[index].name)'")
            }
        } catch {
            Logger.error("Failed to remove tracks from playlist: \(error)")
        }
    }
    
    /// Apply a new track order to a playlist by ID. Reorders the existing in-memory `Track`
    /// objects (preserving their loaded artwork/state) for hot playlists, and persists the
    /// positions to the database. Cold playlists reload lazily, so only the DB is updated.
    func applyPlaylistTrackOrder(playlistID: UUID, orderedTrackIds: [Int64]) async {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[index].type == .regular,
              playlists[index].isContentEditable,
              let dbManager = libraryManager?.databaseManager else { return }

        do {
            // Position-only updates instead of delete-all + reinsert-all.
            try await dbManager.setPlaylistTrackOrder(playlistId: playlistID, orderedTrackIds: orderedTrackIds)

            await MainActor.run {
                guard let index = self.playlists.firstIndex(where: { $0.id == playlistID }) else { return }

                if !self.playlists[index].tracks.isEmpty {
                    let byId = Dictionary(
                        self.playlists[index].tracks.compactMap { track in track.trackId.map { ($0, track) } }
                    ) { first, _ in first }
                    let reordered = orderedTrackIds.compactMap { byId[$0] }
                    if reordered.count == self.playlists[index].tracks.count {
                        self.playlists[index].tracks = reordered
                    }
                }

                self.playlists[index].dateModified = Date()
                Logger.info("Reordered playlist '\(self.playlists[index].name)' (\(orderedTrackIds.count) tracks)")
            }
        } catch {
            Logger.error("Failed to save reordered playlist: \(error)")
        }
    }
}
