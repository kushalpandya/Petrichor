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

    func getTracksBy(filterType: LibraryFilterType, value: String, albumId: Int64? = nil) -> [Track] {
        if filterType.usesMultiArtistParsing && value != filterType.unknownPlaceholder {
            return databaseManager.getTracksByFilterTypeContaining(filterType, value: value)
        } else {
            return databaseManager.getTracksByFilterType(filterType, value: value, albumId: albumId)
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

    func libraryFilterTrackCount(for filterType: LibraryFilterType, value: String, albumId: Int64? = nil) -> Int {
        let items = getLibraryFilterItems(for: filterType)
        if filterType == .albums, let albumId {
            return items.first { $0.albumId == albumId }?.count ?? 0
        }
        return items.first { $0.name == value }?.count ?? 0
    }

    func getTrackCountsByFolderPath() -> [String: Int] {
        databaseManager.getTrackCountsByFolderPath()
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
