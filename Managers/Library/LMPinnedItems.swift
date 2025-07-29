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
    func pinLibraryItem(filterType: LibraryFilterType, filterValue: String) async {
        if filterValue.isEmpty {
            return
        }
        
        // Create the pinned item
        let pinnedItem = PinnedItem(
            filterType: filterType,
            filterValue: filterValue,
            displayName: filterValue,
            subtitle: nil,
            iconName: filterType.icon
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
    func unpinLibraryItem(filterType: LibraryFilterType, filterValue: String) async {
        do {
            try await databaseManager.removePinnedItemMatching(
                filterType: filterType,
                filterValue: filterValue,
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
    func isLibraryItemPinned(filterType: LibraryFilterType, filterValue: String) -> Bool {
        pinnedItems.contains { item in
            item.itemType == .library &&
            item.filterType == filterType &&
            item.filterValue == filterValue
        }
    }
    
    /// Check if an entity is pinned
    func isEntityPinned(_ entity: any Entity) -> Bool {
        pinnedItems.contains { $0.matches(entity: entity) }
    }
    
    /// Get tracks for a pinned item
    func getTracksForPinnedItem(_ item: PinnedItem) -> [Track] {
        // Only handle library items here
        guard item.itemType == .library else { return [] }
        
        return databaseManager.getTracksForPinnedItem(item)
    }
    
    /// Create context menu items for library sidebar
    func createPinContextMenuItem(for filterType: LibraryFilterType, filterValue: String) -> ContextMenuItem {
        let isPinned = isLibraryItemPinned(filterType: filterType, filterValue: filterValue)
        
        return .button(
            title: isPinned ? "Remove from Home" : "Pin to Home",
            role: nil
        ) {
            Task {
                if isPinned {
                    await self.unpinLibraryItem(filterType: filterType, filterValue: filterValue)
                } else {
                    await self.pinLibraryItem(filterType: filterType, filterValue: filterValue)
                }
            }
        }
    }
    
    /// Create context menu items for entity views
    func createPinContextMenuItem(for entity: any Entity) -> ContextMenuItem {
        let isPinned = isEntityPinned(entity)
        
        return .button(
            title: isPinned ? "Remove from Home" : "Pin to Home",
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
