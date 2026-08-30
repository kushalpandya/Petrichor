//
// DatabaseManager class extension
//
// Entity resolution for persisted Discover references. These queries rebuild current rows
// without changing the saved carousel selection.
//

import Foundation
import GRDB

extension DatabaseManager {
    func resolveAlbums(db: Database, albumIds: [Int64], hideDuplicates: Bool) throws -> [DiscoverEntityRow] {
        guard !albumIds.isEmpty else { return [] }
        let countClause = Self.duplicateClause(hideDuplicates, alias: "tc")
        let artistFallbackClause = Self.duplicateClause(hideDuplicates, alias: "ta")
        let sql = """
            SELECT
                al.id AS albumId,
                al.title AS title,
                al.artwork_data AS artwork_data,
                al.release_year AS release_year,
                (SELECT COUNT(*) FROM tracks tc WHERE tc.album_id = al.id \(countClause)) AS trackCount,
                \(Self.albumPrimaryArtist(albumAlias: "al", duplicateClause: artistFallbackClause)) AS artistName
            FROM albums al
            WHERE al.id IN (\(self.databaseQuestionMarks(count: albumIds.count)))
        """

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(albumIds)).compactMap { row in
            let trackCount: Int = row["trackCount"] ?? 0
            guard trackCount > 0 else { return nil }
            let releaseYear: Int? = row["release_year"]
            let artistName: String? = row["artistName"]
            return DiscoverEntityRow(
                ref: .album(id: row["albumId"], title: row["title"] ?? ""),
                trackCount: trackCount,
                artworkData: row["artwork_data"],
                year: releaseYear.map(String.init),
                artistName: (artistName?.isEmpty ?? true) ? nil : artistName
            )
        }
    }

    func resolveArtists(
        db: Database,
        ids: [Int64],
        names: [String],
        hideDuplicates: Bool,
        isImageFetchEnabled: Bool
    ) throws -> [DiscoverEntityRow] {
        guard !ids.isEmpty || !names.isEmpty else { return [] }
        let countClause = Self.duplicateClause(hideDuplicates, alias: "tc")
        // By id where the ref has one; name covers refs persisted before ids were stored.
        let sql = """
            SELECT
                ar.id AS artistId,
                ar.name AS name,
                ar.artwork_data AS artwork_data,
                ar.image_source AS image_source,
                (SELECT COUNT(DISTINCT ta.track_id)
                 FROM track_artists ta
                 JOIN tracks tc ON tc.id = ta.track_id \(countClause)
                 WHERE ta.artist_id = ar.id AND ta.role = 'artist') AS trackCount
            FROM artists ar
            WHERE ar.id IN (\(self.databaseQuestionMarks(count: ids.count)))
           OR ar.name IN (\(self.databaseQuestionMarks(count: names.count)))
        """

        var argumentValues: [any DatabaseValueConvertible] = ids
        argumentValues.append(contentsOf: names)
        return try Row.fetchAll(db, sql: sql, arguments: Self.arguments(argumentValues)).compactMap { row in
            let trackCount: Int = row["trackCount"] ?? 0
            guard trackCount > 0 else { return nil }
            return DiscoverEntityRow(
                ref: .artist(id: row["artistId"], name: row["name"] ?? ""),
                trackCount: trackCount,
                artworkData: Self.artistArtwork(row: row, isImageFetchEnabled: isImageFetchEnabled),
                year: nil,
                artistName: nil
            )
        }
    }

    func resolvePlaylists(db: Database, playlistIds: [UUID], hideDuplicates: Bool) throws -> [DiscoverEntityRow] {
        guard !playlistIds.isEmpty else { return [] }
        let countClause = Self.duplicateClause(hideDuplicates, alias: "tc")
        let sql = """
            SELECT
                p.id AS playlistId,
                p.name AS name,
                (SELECT COUNT(*) FROM playlist_tracks pt
                  JOIN tracks tc ON tc.id = pt.track_id \(countClause)
                 WHERE pt.playlist_id = p.id) AS trackCount
            FROM playlists p
            WHERE p.id IN (\(self.databaseQuestionMarks(count: playlistIds.count)))
        """

        let arguments = StatementArguments(playlistIds.map { $0.uuidString })
        return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
            guard let idString: String = row["playlistId"],
                  let playlistId = UUID(uuidString: idString) else { return nil }
            let trackCount: Int = row["trackCount"] ?? 0
            guard trackCount > 0 else { return nil }
            return DiscoverEntityRow(
                ref: .playlist(id: playlistId, name: row["name"] ?? ""),
                trackCount: trackCount,
                artworkData: nil,
                year: nil,
                artistName: nil
            )
        }
    }
}
