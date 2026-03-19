import Foundation
import GRDB

struct PlaylistTrack: Codable, FetchableRecord, PersistableRecord {
    let playlistId: String
    let trackId: Int64
    let position: Int
    let dateAdded: Date

    // MARK: - DB Configuration

    static let databaseTableName = "playlist_tracks"

    enum Columns {
        static let playlistId = Column("playlist_id")
        static let trackId = Column("track_id")
        static let position = Column("position")
        static let dateAdded = Column("date_added")
    }

    // MARK: - FetchableRecord
    init(row: Row) throws {
        playlistId = row[Columns.playlistId]
        trackId = row[Columns.trackId]
        position = row[Columns.position]
        dateAdded = row[Columns.dateAdded]
    }

    // MARK: - Initialization
    init(playlistId: String, trackId: Int64, position: Int, dateAdded: Date = Date()) {
        self.playlistId = playlistId
        self.trackId = trackId
        self.position = position
        self.dateAdded = dateAdded
    }

    // MARK: - PersistableRecord
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.playlistId] = playlistId
        container[Columns.trackId] = trackId
        container[Columns.position] = position
        container[Columns.dateAdded] = dateAdded
    }

    // MARK: - Associations
    static let track = belongsTo(Track.self, using: ForeignKey(["track_id"]))
    static let playlist = belongsTo(Playlist.self, using: ForeignKey(["playlist_id"]))
}

extension PlaylistTrack {
    /// Insert multiple PlaylistTrack records efficiently
    static func insertMany(_ playlistTracks: [PlaylistTrack], db: Database) throws {
        try playlistTracks.forEach { try $0.insert(db, onConflict: .ignore) }
    }
}
