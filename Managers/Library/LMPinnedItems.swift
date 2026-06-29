//
// LibraryManager class extension
//
// This extension contains methods managing pinned items in the library,
// the methods internally also use DatabaseManager methods to work with database.
//

import Foundation
import SwiftUI

extension LibraryManager {
    // MARK: - Pinned Items Management
    
    /// Load pinned items from database
    func loadPinnedItems() async {
        do {
            let items = try await databaseManager.getPinnedItems()
            await MainActor.run {
                self.pinnedItems = items
            }
        } catch {
            Logger.error("Failed to load pinned items: \(error)")
        }
    }
    
    /// Pin a library filter item (from sidebar)
    func pinLibraryItem(filterType: LibraryFilterType, filterValue: String, albumId: Int64? = nil) async {
        if filterValue.isEmpty {
            return
        }

        // Create the pinned item
        let pinnedItem = PinnedItem(
            filterType: filterType,
            filterValue: filterValue,
            displayName: filterValue,
            subtitle: nil,
            albumId: albumId
        )
        
        do {
            try await databaseManager.savePinnedItem(pinnedItem)
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to pin item: \(error)")
        }
    }
    
    /// Pin an artist entity (from entity view)
    func pinArtistEntity(_ artist: ArtistEntity) async {
        // Try to find the artist in the database to get its ID
        let artistId = databaseManager.getArtistId(for: artist.name)
        
        let pinnedItem = PinnedItem(
            artistEntity: artist,
            artistId: artistId
        )
        
        do {
            try await databaseManager.savePinnedItem(pinnedItem)
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to pin artist: \(error)")
        }
    }
    
    /// Pin an album entity (from entity view)
    func pinAlbumEntity(_ album: AlbumEntity) async {
        let pinnedItem = PinnedItem(albumEntity: album)
        
        do {
            try await databaseManager.savePinnedItem(pinnedItem)
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to pin album: \(error)")
        }
    }
    
    /// Unpin a library item
    func unpinLibraryItem(filterType: LibraryFilterType, filterValue: String, albumId: Int64? = nil) async {
        do {
            try await databaseManager.removePinnedItemMatching(
                filterType: filterType,
                filterValue: filterValue,
                albumId: albumId,
                playlistId: nil
            )
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to unpin item: \(error)")
        }
    }
    
    /// Unpin an entity (artist or album)
    func unpinEntity(_ entity: any Entity) async {
        // Find the matching pinned item
        guard let pinnedItem = pinnedItems.first(where: { $0.matches(entity: entity) }) else {
            return
        }
        
        do {
            try await databaseManager.removePinnedItem(pinnedItem)
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to unpin entity: \(error)")
        }
    }
    
    /// Remove a pinned item from home
    func removePinnedItem(_ item: PinnedItem) async {
        do {
            try await databaseManager.removePinnedItem(item)
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to remove pinned item: \(error)")
        }
    }
    
    /// Reorder pinned items
    func reorderPinnedItems(_ items: [PinnedItem]) async {
        do {
            try await databaseManager.updatePinnedItemsOrder(items)
            await MainActor.run {
                self.pinnedItems = items
            }
        } catch {
            Logger.error("Failed to reorder pinned items: \(error)")
        }
    }
    
    /// Check if a library filter item is pinned
    func isLibraryItemPinned(filterType: LibraryFilterType, filterValue: String, albumId: Int64? = nil) -> Bool {
        pinnedItems.contains { item in
            guard item.itemType == .library else { return false }
            // Albums match strictly by id (legacy nil-albumId pins are backfilled on upgrade).
            if filterType == .albums, let albumId {
                return item.albumId == albumId
            }
            return item.filterType == filterType && item.filterValue == filterValue
        }
    }
    
    /// Check if an entity is pinned
    func isEntityPinned(_ entity: any Entity) -> Bool {
        pinnedItems.contains { $0.matches(entity: entity) }
    }
    
    /// Pin a folder by its absolute path (sub-folders aren't DB records, so identity is the path)
    func pinFolder(path: String, name: String) async {
        if path.isEmpty {
            return
        }

        let pinnedItem = PinnedItem(folderPath: path, name: name)

        do {
            try await databaseManager.savePinnedItem(pinnedItem)
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to pin folder: \(error)")
        }
    }

    /// Unpin a folder by its absolute path
    func unpinFolder(path: String) async {
        guard let pinnedItem = pinnedItems.first(where: {
            $0.itemType == .folder && $0.filterValue == path
        }) else {
            return
        }

        do {
            try await databaseManager.removePinnedItem(pinnedItem)
            await loadPinnedItems()
        } catch {
            Logger.error("Failed to unpin folder: \(error)")
        }
    }

    /// Check if a folder is pinned by its absolute path
    func isFolderPinned(path: String) -> Bool {
        pinnedItems.contains { $0.itemType == .folder && $0.filterValue == path }
    }

    /// Get tracks for a pinned item
    func getTracksForPinnedItem(_ item: PinnedItem) -> [Track] {
        // Library and folder items resolve through the database; playlists are handled elsewhere.
        guard item.itemType == .library || item.itemType == .folder else { return [] }

        return databaseManager.getTracksForPinnedItem(item)
    }

    /// Get track counts for multiple pinned items.
    /// Library counts are sourced from `cachedLibraryCategories` so they cannot diverge
    /// from what the Library sidebar displays. Playlist counts come from the database.
    func getTrackCountForPinnedItems(_ items: [PinnedItem]) async -> [Int64: Int] {
        var counts: [Int64: Int] = [:]

        // Library counts read (and lazily populate) `cachedLibraryCategories`, which is also
        // mutated by refreshLibraryCategories/loadLibraryCategories on the MainActor. This
        // method can run off-main, so do the cache-touching work on the MainActor to keep all
        // access to that dictionary serialized.
        let libraryItems = items.filter { $0.itemType == .library }
        if !libraryItems.isEmpty {
            counts = await MainActor.run {
                var libraryCounts: [Int64: Int] = [:]
                for item in libraryItems {
                    guard let id = item.id,
                          let filterType = item.filterType,
                          let filterValue = item.filterValue else { continue }
                    libraryCounts[id] = self.libraryFilterTrackCount(for: filterType, value: filterValue, albumId: item.albumId)
                }
                return libraryCounts
            }
        }

        let playlistItems = items.filter { $0.itemType == .playlist }
        if !playlistItems.isEmpty {
            let playlistCounts = await databaseManager.getTrackCountForPinnedPlaylists(playlistItems)
            for (id, count) in playlistCounts {
                counts[id] = count
            }
        }

        // Folder counts come from the database; cachedLibraryCategories only covers filter types.
        let folderItems = items.filter { $0.itemType == .folder }
        for item in folderItems {
            guard let id = item.id, let path = item.filterValue else { continue }
            counts[id] = databaseManager.getImmediateTrackCountForFolderPath(path)
        }

        return counts
    }
    
    /// Create context menu items for library sidebar
    func createPinContextMenuItem(for filterType: LibraryFilterType, filterValue: String, albumId: Int64? = nil) -> ContextMenuItem {
        let isPinned = isLibraryItemPinned(filterType: filterType, filterValue: filterValue, albumId: albumId)

        return .button(
            title: isPinned ? String(localized: "Remove from Home") : String(localized: "Pin to Home"),
            role: nil
        ) {
            Task {
                if isPinned {
                    await self.unpinLibraryItem(filterType: filterType, filterValue: filterValue, albumId: albumId)
                } else {
                    await self.pinLibraryItem(filterType: filterType, filterValue: filterValue, albumId: albumId)
                }
            }
        }
    }
    
    /// Create context menu items for entity views
    func createPinContextMenuItem(for entity: any Entity) -> ContextMenuItem {
        let isPinned = isEntityPinned(entity)
        
        return .button(
            title: isPinned ? String(localized: "Remove from Home") : String(localized: "Pin to Home"),
            role: nil
        ) {
            Task {
                if isPinned {
                    await self.unpinEntity(entity)
                } else {
                    if let artist = entity as? ArtistEntity {
                        await self.pinArtistEntity(artist)
                    } else if let album = entity as? AlbumEntity {
                        await self.pinAlbumEntity(album)
                    }
                }
            }
        }
    }
}
