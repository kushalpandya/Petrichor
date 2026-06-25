import Foundation
import GRDB

/// Maps a normalized old artist name to the canonical artist it was merged into.
/// Insert uses REPLACE so re-merging an alias updates its target.
struct ArtistAlias: FetchableRecord, PersistableRecord {
    let normalizedAlias: String
    let displayName: String
    let canonicalArtistId: Int64
    var createdAt: Date?

    static let databaseTableName = "artist_aliases"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    enum Columns {
        static let normalizedAlias = Column("normalized_alias")
        static let displayName = Column("display_name")
        static let canonicalArtistId = Column("canonical_artist_id")
        static let createdAt = Column("created_at")
    }

    init(normalizedAlias: String, displayName: String, canonicalArtistId: Int64, createdAt: Date? = nil) {
        self.normalizedAlias = normalizedAlias
        self.displayName = displayName
        self.canonicalArtistId = canonicalArtistId
        self.createdAt = createdAt
    }

    init(row: Row) throws {
        normalizedAlias = row[Columns.normalizedAlias]
        displayName = row[Columns.displayName]
        canonicalArtistId = row[Columns.canonicalArtistId]
        createdAt = row[Columns.createdAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.normalizedAlias] = normalizedAlias
        container[Columns.displayName] = displayName
        container[Columns.canonicalArtistId] = canonicalArtistId
        container[Columns.createdAt] = createdAt ?? Date()
    }
}
