import Foundation
import GRDB

/// Maps a normalized album key (title|primary-artist) to the canonical album it was
/// merged into. Insert uses REPLACE so re-merging an alias updates its target.
struct AlbumAlias: FetchableRecord, PersistableRecord {
    let normalizedKey: String
    let displayTitle: String
    let canonicalAlbumId: Int64
    var createdAt: Date?

    static let databaseTableName = "album_aliases"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    enum Columns {
        static let normalizedKey = Column("normalized_key")
        static let displayTitle = Column("display_title")
        static let canonicalAlbumId = Column("canonical_album_id")
        static let createdAt = Column("created_at")
    }

    init(normalizedKey: String, displayTitle: String, canonicalAlbumId: Int64, createdAt: Date? = nil) {
        self.normalizedKey = normalizedKey
        self.displayTitle = displayTitle
        self.canonicalAlbumId = canonicalAlbumId
        self.createdAt = createdAt
    }

    init(row: Row) throws {
        normalizedKey = row[Columns.normalizedKey]
        displayTitle = row[Columns.displayTitle]
        canonicalAlbumId = row[Columns.canonicalAlbumId]
        createdAt = row[Columns.createdAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.normalizedKey] = normalizedKey
        container[Columns.displayTitle] = displayTitle
        container[Columns.canonicalAlbumId] = canonicalAlbumId
        container[Columns.createdAt] = createdAt ?? Date()
    }
}
