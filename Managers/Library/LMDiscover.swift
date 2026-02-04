import Foundation

extension LibraryManager {
    // MARK: - Constants
    private static let discoverTrackIdsKey = "discoverTrackIds"
    private static let discoverLastUpdatedKey = "discoverLastUpdated"
    private static let discoverUpdateIntervalKey = "discoverUpdateInterval"
    private static let discoverTrackCountKey = "discoverTrackCount"
    
    private var discoverUpdateInterval: DiscoverUpdateInterval {
        let rawValue = userDefaults.string(forKey: Self.discoverUpdateIntervalKey) ?? DiscoverUpdateInterval.weekly.rawValue
        return DiscoverUpdateInterval(rawValue: rawValue) ?? .weekly
    }
    
    private var discoverTrackCount: Int {
        let count = userDefaults.integer(forKey: Self.discoverTrackCountKey)
        return count > 0 ? count : 50
    }
    
    var discoverLastUpdated: Date? {
        userDefaults.object(forKey: Self.discoverLastUpdatedKey) as? Date
    }
    
    // MARK: - Methods
    
    func loadDiscoverTracks() {
        var tracks: [Track]
        
        if shouldRefreshDiscover() {
            // Generate new discover list
            tracks = databaseManager.getDiscoverTracks(limit: discoverTrackCount)
            
            // Save track IDs
            let trackIds = tracks.compactMap { $0.trackId }
            userDefaults.set(trackIds, forKey: Self.discoverTrackIdsKey)
            userDefaults.set(Date(), forKey: Self.discoverLastUpdatedKey)
        } else {
            // Load from saved IDs
            if let savedIds = userDefaults.array(forKey: Self.discoverTrackIdsKey) as? [Int64] {
                tracks = databaseManager.getTracks(byIds: savedIds)
                // Populate album artwork for loaded tracks
                databaseManager.populateAlbumArtworkForTracks(&tracks)
            } else {
                // No saved tracks, generate new
                tracks = databaseManager.getDiscoverTracks(limit: discoverTrackCount)
                
                // Save track IDs
                let trackIds = tracks.compactMap { $0.trackId }
                userDefaults.set(trackIds, forKey: Self.discoverTrackIdsKey)
                userDefaults.set(Date(), forKey: Self.discoverLastUpdatedKey)
            }
        }
        
        self.discoverTracks = tracks
        Logger.info("Discover tracks loaded")
    }
    
    /// Force refresh discover tracks (called when settings change)
    func refreshDiscoverTracks() {
        Logger.info("Force refreshing discover tracks")
        
        // Clear the last updated date to force refresh
        userDefaults.removeObject(forKey: Self.discoverLastUpdatedKey)
        
        // Clear current tracks to force UI update
        self.discoverTracks = []
        
        // Reload tracks immediately
        loadDiscoverTracks()
        
        // Force UI update by triggering objectWillChange
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }
    
    /// Check if discover list needs refresh
    private func shouldRefreshDiscover() -> Bool {
        guard let lastUpdated = userDefaults.object(forKey: Self.discoverLastUpdatedKey) as? Date else {
            return true // Never updated
        }
        
        let timeElapsed = Date().timeIntervalSince(lastUpdated)
        return timeElapsed >= discoverUpdateInterval.timeInterval
    }
    
    /// Generate new discover tracks
    private func generateDiscoverTracks() async -> [Track] {
        let tracks = await Task.detached {
            self.databaseManager.getDiscoverTracks(limit: self.discoverTrackCount)
        }.value
        
        // Save track IDs
        let trackIds = tracks.compactMap { $0.trackId }
        userDefaults.set(trackIds, forKey: Self.discoverTrackIdsKey)
        userDefaults.set(Date(), forKey: Self.discoverLastUpdatedKey)
        
        return tracks
    }
}
