//
// PlaylistManager class extension
//
// This extension contains methods for doing CRUD operations on regular playlists,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation

extension PlaylistManager {
    /// Update all smart playlists with current track data
    func updateSmartPlaylists() {
        guard libraryManager != nil else { return }
        
        Logger.info("Updating smart playlists")
        
        for index in playlists.indices {
            guard playlists[index].type == .smart else { continue }
            
            Task {
                await loadSmartPlaylistTracks(playlists[index])
            }
        }
    }
    
    /// Load tracks for a smart playlist on-demand
    func loadSmartPlaylistTracks(_ playlist: Playlist) async {
        guard playlist.type == .smart,
              let libraryManager = libraryManager else { return }
        
        do {
            let tracks = try await libraryManager.databaseManager.getTracksForSmartPlaylist(playlist)
            
            // Update playlist on main thread
            await MainActor.run {
                if let index = self.playlists.firstIndex(where: { $0.id == playlist.id }) {
                    self.playlists[index].tracks = tracks
                    self.playlists[index].trackCount = tracks.count
                    Logger.info("Loaded \(tracks.count) tracks for smart playlist '\(playlist.name)'")
                }
            }
        } catch {
            Logger.error("Failed to load tracks for smart playlist '\(playlist.name)': \(error)")
        }
    }
    
    /// Check if a smart playlist needs its tracks refreshed
    func smartPlaylistNeedsRefresh(_ playlist: Playlist) -> Bool {
        guard playlist.type == .smart else { return false }
        
        // If tracks array is empty, it needs refresh
        // (unless it's genuinely empty based on criteria)
        return playlist.tracks.isEmpty && playlist.dateModified != playlist.dateCreated
    }

    /// Get tracks for a smart playlist from database
    private func getSmartPlaylistTracks(_ playlist: Playlist) -> [Track] {
        guard let manager = libraryManager else { return [] }
        
        return manager.databaseManager.getTracksForSmartPlaylistSync(playlist)
    }
}
