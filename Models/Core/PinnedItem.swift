import Foundation
import GRDB

struct PinnedItem: Identifiable, FetchableRecord, PersistableRecord {
    var id: Int64?
    let itemType: ItemType
    let filterType: LibraryFilterType?
    let filterValue: String?
    let entityId: UUID?
    let artistId: Int64?
    let albumId: Int64?
    let playlistId: UUID?
    let displayName: String
    let subtitle: String?
    let iconName: String
    var sortOrder: Int
    let dateAdded: Date
    
    enum ItemType: String, Codable {
        case library
        case playlist
    }
    
    // MARK: - Initialization
    
    // For library sidebar items
    init(filterType: LibraryFilterType, filterValue: String, displayName: String, subtitle: String? = nil, iconName: String) {
        self.itemType = .library
        self.filterType = filterType
        self.filterValue = filterValue
        self.entityId = nil
        self.artistId = nil
        self.albumId = nil
        self.playlistId = nil
        self.displayName = displayName
        self.subtitle = subtitle
        self.iconName = iconName
        self.sortOrder = 0
        self.dateAdded = Date()
    }
    
    // For artist entities
    init(artistEntity: ArtistEntity, artistId: Int64? = nil) {
        self.itemType = .library
        self.filterType = .artists
        self.filterValue = artistEntity.name
        self.entityId = artistEntity.id
        self.artistId = artistId
        self.albumId = nil
        self.playlistId = nil
        self.displayName = artistEntity.name
        self.subtitle = artistEntity.subtitle
        self.iconName = Icons.personFill
        self.sortOrder = 0
        self.dateAdded = Date()
    }
    
    // For album entities
    init(albumEntity: AlbumEntity) {
        self.itemType = .library
        self.filterType = .albums
        self.filterValue = albumEntity.name
        self.entityId = albumEntity.id
        self.artistId = nil
        self.albumId = albumEntity.albumId
        self.playlistId = nil
        self.displayName = albumEntity.name
        self.subtitle = albumEntity.year
        self.iconName = Icons.opticalDiscFill
        self.sortOrder = 0
        self.dateAdded = Date()
    }
    
    // For playlists
    init(playlist: Playlist) {
        self.itemType = .playlist
        self.filterType = nil
        self.filterValue = nil
        self.entityId = nil
        self.artistId = nil
        self.albumId = nil
        self.playlistId = playlist.id
        self.displayName = playlist.name
        self.subtitle = "\(playlist.trackCount) songs"
        self.iconName = Icons.defaultPlaylistIcon(for: playlist)
        self.sortOrder = 0
        self.dateAdded = Date()
    }
    
    // MARK: - GRDB Configuration
    
    static let databaseTableName = "pinned_items"
    
    enum Columns {
        static let id = Column("id")
        static let itemType = Column("item_type")
        static let filterType = Column("filter_type")
        static let filterValue = Column("filter_value")
        static let entityId = Column("entity_id")
        static let artistId = Column("artist_id")
        static let albumId = Column("album_id")
        static let playlistId = Column("playlist_id")
        static let displayName = Column("display_name")
        static let subtitle = Column("subtitle")
        static let iconName = Column("icon_name")
        static let sortOrder = Column("sort_order")
        static let dateAdded = Column("date_added")
    }
    
    // MARK: - FetchableRecord
    
    init(row: Row) throws {
        id = row[Columns.id]
        itemType = ItemType(rawValue: row[Columns.itemType]) ?? .library
        
        // Properly cast String values
        if let filterTypeString: String = row[Columns.filterType] {
            filterType = LibraryFilterType(rawValue: filterTypeString)
        } else {
            filterType = nil
        }
        
        filterValue = row[Columns.filterValue]
        
        if let entityIdString: String = row[Columns.entityId] {
            entityId = UUID(uuidString: entityIdString)
        } else {
            entityId = nil
        }
        
        artistId = row[Columns.artistId]
        albumId = row[Columns.albumId]
        
        if let playlistIdString: String = row[Columns.playlistId] {
            playlistId = UUID(uuidString: playlistIdString)
        } else {
            playlistId = nil
        }
        
        displayName = row[Columns.displayName]
        subtitle = row[Columns.subtitle]
        iconName = row[Columns.iconName]
        sortOrder = row[Columns.sortOrder]
        dateAdded = row[Columns.dateAdded]
    }
    
    // MARK: - PersistableRecord
    
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.itemType] = itemType.rawValue
        container[Columns.filterType] = filterType?.rawValue
        container[Columns.filterValue] = filterValue
        container[Columns.entityId] = entityId?.uuidString
        container[Columns.artistId] = artistId
        container[Columns.albumId] = albumId
        container[Columns.playlistId] = playlistId?.uuidString
        container[Columns.displayName] = displayName
        container[Columns.subtitle] = subtitle
        container[Columns.iconName] = iconName
        container[Columns.sortOrder] = sortOrder
        container[Columns.dateAdded] = dateAdded
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    // MARK: - Helper Methods
    
    /// Check if this pinned item matches a given library filter item
    func matches(filterItem: LibraryFilterItem) -> Bool {
        guard itemType == .library,
              let filterType = filterType else { return false }
        
        return filterType == filterItem.filterType && filterValue == filterItem.name
    }
    
    /// Check if this pinned item matches a given entity
    func matches(entity: any Entity) -> Bool {
        guard itemType == .library else { return false }
        
        // First try to match by entity ID if available
        if let entityId = entityId, entityId == entity.id {
            return true
        }
        
        // Then try to match by name and type
        if let filterType = filterType {
            switch filterType {
            case .artists:
                return entity is ArtistEntity && filterValue == entity.name
            case .albums:
                if let albumEntity = entity as? AlbumEntity {
                    // For albums, also check if we have a matching album ID
                    if let albumId = albumId, albumId == albumEntity.albumId {
                        return true
                    }
                    return filterValue == entity.name
                }
                return false
            default:
                return false
            }
        }
        
        return false
    }
    
    /// Check if this pinned item matches a given playlist
    func matches(playlist: Playlist) -> Bool {
        itemType == .playlist && playlistId == playlist.id
    }
}

// MARK: - Equatable Conformance
extension PinnedItem: Equatable {
    static func == (lhs: PinnedItem, rhs: PinnedItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.itemType == rhs.itemType &&
        lhs.filterType == rhs.filterType &&
        lhs.filterValue == rhs.filterValue &&
        lhs.entityId == rhs.entityId &&
        lhs.artistId == rhs.artistId &&
        lhs.albumId == rhs.albumId &&
        lhs.playlistId == rhs.playlistId &&
        lhs.displayName == rhs.displayName &&
        lhs.subtitle == rhs.subtitle &&
        lhs.iconName == rhs.iconName &&
        lhs.sortOrder == rhs.sortOrder
    }
}
