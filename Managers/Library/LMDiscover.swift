import Foundation

extension LibraryManager {
    // MARK: - Constants
    private static let discoverTrackIdsKey = "DiscoverTrackIds"
    private static let discoverLastUpdatedKey = "DiscoverLastUpdated"
    private static let discoverUpdateIntervalKey = "DiscoverUpdateInterval"
    
    enum DiscoverUpdateInterval: String, CaseIterable {
        case daily = "Daily"
        case weekly = "Weekly"
        case biweekly = "Biweekly"
        case monthly = "Monthly"
        
        var timeInterval: TimeInterval {
            switch self {
            case .daily: return 86400 // 1 day
            case .weekly: return 604800 // 7 days
            case .biweekly: return 1209600 // 14 days
            case .monthly: return 2592000 // 30 days
            }
        }
    }
    
    private var discoverUpdateInterval: DiscoverUpdateInterval {
        let rawValue = userDefaults.string(forKey: Self.discoverUpdateIntervalKey) ?? DiscoverUpdateInterval.weekly.rawValue
        return DiscoverUpdateInterval(rawValue: rawValue) ?? .weekly
    }
    
    // MARK: - Methods
    
    func loadDiscoverTracks() {
        var tracks: [Track]
        
        if shouldRefreshDiscover() {
            // Generate new discover list
            tracks = databaseManager.getDiscoverTracks(limit: 50)
            
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
                tracks = databaseManager.getDiscoverTracks(limit: 50)
                
                // Save track IDs
                let trackIds = tracks.compactMap { $0.trackId }
                userDefaults.set(trackIds, forKey: Self.discoverTrackIdsKey)
                userDefaults.set(Date(), forKey: Self.discoverLastUpdatedKey)
            }
        }
        
        self.discoverTracks = tracks
        Logger.info("Discover tracks loaded")
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
            self.databaseManager.getDiscoverTracks(limit: 50)
        }.value
        
        // Save track IDs
        let trackIds = tracks.compactMap { $0.trackId }
        userDefaults.set(trackIds, forKey: Self.discoverTrackIdsKey)
        userDefaults.set(Date(), forKey: Self.discoverLastUpdatedKey)
        
        return tracks
    }
}
