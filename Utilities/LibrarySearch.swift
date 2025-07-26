import Foundation

struct LibrarySearch {
    // MARK: - Track Search

    /// Searches tracks based on a query string using FTS5
    /// - Parameters:
    ///   - tracks: The tracks to search through (used as fallback if FTS fails)
    ///   - query: The search query string
    /// - Returns: Filtered tracks that match the query
    static func searchTracks(_ tracks: [Track], with query: String) -> [Track] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return tracks }

        // Use FTS5 search from database
        if let coordinator = AppCoordinator.shared {
            let ftsResults = coordinator.libraryManager.databaseManager.searchTracksUsingFTS(trimmedQuery)
            
            // Return FTS results if we got any
            if !ftsResults.isEmpty {
                return ftsResults
            }
            
            // If FTS returned empty but query exists, it means no matches found
            // Return empty array rather than falling back to in-memory search
            return []
        }

        // If no coordinator available (shouldn't happen in normal app flow)
        // Return empty results
        Logger.warning("AppCoordinator not available for search")
        return []
    }
    
    // MARK: - Search Result Ranking

    /// Searches and ranks tracks by relevance using FTS5
    static func searchTracksWithRanking(_ tracks: [Track], with query: String) -> [Track] {
        // FTS5 already returns ranked results, so just use the regular search
        searchTracks(tracks, with: query)
    }
}
