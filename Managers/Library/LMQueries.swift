//
// LibraryManager class extension
//
// This extension contains methods querying tracks across Library,
// the methods internally use DatabaseManager methods to work with database.
//

import Foundation

extension LibraryManager {
    func getTracksInFolder(_ folder: Folder) -> [Track] {
        guard let folderId = folder.id else {
            Logger.error("Folder has no ID")
            return []
        }

        return databaseManager.getTracksForFolder(folderId)
    }

    func getTrackCountForFolder(_ folder: Folder) -> Int {
        guard let folderId = folder.id else { return 0 }

        // Check cache first
        if let cachedCount = folderTrackCounts[folderId] {
            return cachedCount
        }

        // Get count from database (this should be a fast query)
        let tracks = databaseManager.getTracksForFolder(folderId)
        let count = tracks.count

        // Cache it
        folderTrackCounts[folderId] = count

        return count
    }

    func getTracksBy(filterType: LibraryFilterType, value: String) -> [Track] {
        if filterType.usesMultiArtistParsing && value != filterType.unknownPlaceholder {
            return databaseManager.getTracksByFilterTypeContaining(filterType, value: value)
        } else {
            return databaseManager.getTracksByFilterType(filterType, value: value)
        }
    }

    func getLibraryFilterItems(for filterType: LibraryFilterType) -> [LibraryFilterItem] {
        if let cachedItems = cachedLibraryCategories[filterType] {
            Logger.info("Returning cached library filter items for \(filterType)")
            return cachedItems
        }
        
        let items = getLibraryFilterItemsFromDatabase(for: filterType)
        cachedLibraryCategories[filterType] = items
        
        return items
    }

    func getDistinctValues(for filterType: LibraryFilterType) -> [String] {
        databaseManager.getDistinctValues(for: filterType)
    }

    func updateSearchResults() {
        if globalSearchText.isEmpty {
            // When not searching, don't populate searchResults with all tracks
            searchResults = []
        } else {
            // Use LibrarySearch which uses FTS from database
            searchResults = LibrarySearch.searchTracks(tracks, with: globalSearchText)
        }
    }
}
