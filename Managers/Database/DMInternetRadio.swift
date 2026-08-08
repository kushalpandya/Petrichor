//
// DatabaseManager class extension
//
// This extension contains the methods for managing internet radio stations and collections.
//

import Foundation
import GRDB

enum StationCollectionError: Error {
    case notFound
}

extension DatabaseManager {
    // MARK: - Stations

    func loadAllStations() -> [RadioStation] {
        do {
            return try dbQueue.read { db in
                try RadioStation.order(RadioStation.Columns.name).fetchAll(db)
            }
        } catch {
            Logger.error("Failed to load radio stations: \(error)")
            return []
        }
    }

    /// A single station, for the launch restore, which must not read the whole table.
    func loadStation(id stationId: Int64) -> RadioStation? {
        do {
            return try dbQueue.read { db in
                try RadioStation.filter(RadioStation.Columns.id == stationId).fetchOne(db)
            }
        } catch {
            Logger.error("Failed to load radio station \(stationId): \(error)")
            return nil
        }
    }

    @discardableResult
    func saveStation(_ station: RadioStation) async throws -> RadioStation {
        try await dbQueue.write { db in
            var saved = station
            // `save` writes back the assigned rowID through `didInsert`.
            try saved.save(db)
            return saved
        }
    }

    /// Artwork only; the starter-set download inserts first and fills images in after.
    ///
    /// Fills a blank only, and reports whether it did: a favicon can land long after the
    /// station is on screen, and must not overwrite artwork the user set in the meantime.
    @discardableResult
    func updateStationArtwork(id stationId: Int64, artwork: Data) async throws -> Bool {
        try await dbQueue.write { db in
            try RadioStation
                .filter(RadioStation.Columns.id == stationId)
                .filter(RadioStation.Columns.artworkData == nil)
                .updateAll(
                    db,
                    RadioStation.Columns.artworkData.set(to: artwork),
                    RadioStation.Columns.dateModified.set(to: Date())
                ) > 0
        }
    }

    /// Only the user-editable columns. Statistics belong to whatever credited a play while
    /// the editor was open, and `artwork == nil` leaves a favicon that backfilled meanwhile
    /// in place; `.some(nil)` is an explicit clear.
    func updateStationDetails(
        id stationId: Int64,
        name: String,
        streamURL: String,
        description: String?,
        artwork: Data??
    ) async throws {
        _ = try await dbQueue.write { db in
            var assignments: [ColumnAssignment] = [
                RadioStation.Columns.name.set(to: name),
                RadioStation.Columns.streamURL.set(to: streamURL),
                RadioStation.Columns.description.set(to: description),
                RadioStation.Columns.dateModified.set(to: Date())
            ]
            if case .some(let value) = artwork {
                assignments.append(RadioStation.Columns.artworkData.set(to: value))
            }

            let updated = try RadioStation.filter(RadioStation.Columns.id == stationId).updateAll(db, assignments)
            // Zero rows means the station was deleted while its editor was open; reporting
            // success would close the sheet as though the edit had been kept.
            guard updated == 1 else { throw StationCollectionError.notFound }
            return updated
        }
    }

    func deleteStations(ids: Set<Int64>) async throws -> Set<Int64> {
        try await dbQueue.write { db in
            let existing = Set(try RadioStation
                .select(RadioStation.Columns.id, as: Int64.self)
                .filter(ids.contains(RadioStation.Columns.id))
                .fetchAll(db))
            guard !existing.isEmpty else { return [] }
            try RadioStation.filter(existing.contains(RadioStation.Columns.id)).deleteAll(db)
            return existing
        }
    }

    /// `+= 1` compiles to `play_count = play_count + 1`, so a concurrent edit can't
    /// clobber the count with a stale in-memory copy.
    func incrementStationPlayCount(id stationId: Int64) async throws {
        _ = try await dbQueue.write { db in
            try RadioStation
                .filter(RadioStation.Columns.id == stationId)
                .updateAll(
                    db,
                    RadioStation.Columns.playCount += 1,
                    RadioStation.Columns.lastPlayed.set(to: Date())
                )
        }
    }

    /// Known identities, so a repeat download doesn't duplicate stations.
    func existingStationIdentities() -> (uuids: Set<String>, urls: Set<String>) {
        do {
            return try dbQueue.read { db in
                let rows = try RadioStation
                    .select(RadioStation.Columns.stationUUID, RadioStation.Columns.streamURL)
                    .asRequest(of: Row.self)
                    .fetchAll(db)
                var uuids = Set<String>()
                var urls = Set<String>()
                for row in rows {
                    if let uuid: String = row["station_uuid"], !uuid.isEmpty { uuids.insert(uuid) }
                    if let url: String = row["stream_url"] { urls.insert(url) }
                }
                return (uuids, urls)
            }
        } catch {
            Logger.error("Failed to read existing station identities: \(error)")
            return ([], [])
        }
    }

    // MARK: - Station Collections

    func loadStations(forPlaylist playlistId: UUID) -> [RadioStation] {
        do {
            return try dbQueue.read { db in
                let sql = """
                    SELECT r.* FROM internet_radio r
                    JOIN playlist_stations ps ON ps.station_id = r.id
                    WHERE ps.playlist_id = ?
                    ORDER BY ps.position
                """
                return try RadioStation.fetchAll(db, sql: sql, arguments: [playlistId.uuidString])
            }
        } catch {
            Logger.error("Failed to load stations for collection \(playlistId): \(error)")
            return []
        }
    }

    func collectionIds(containingAll stationIds: [Int64]) -> Set<UUID> {
        let distinct = Set(stationIds)
        guard !distinct.isEmpty else { return [] }

        do {
            return try dbQueue.read { db in
                let ids = try PlaylistStation
                    .select(PlaylistStation.Columns.playlistId, as: String.self)
                    .filter(distinct.contains(PlaylistStation.Columns.stationId))
                    .group(PlaylistStation.Columns.playlistId)
                    .having(count(distinct: PlaylistStation.Columns.stationId) == distinct.count)
                    .fetchAll(db)
                return Set(ids.compactMap(UUID.init(uuidString:)))
            }
        } catch {
            Logger.error("Failed to read collections for \(distinct.count) station(s): \(error)")
            return []
        }
    }

    /// Playlist row and membership together: two transactions would leave an empty
    /// collection committed when the membership insert failed.
    func createStationCollection(_ playlist: Playlist, orderedStationIds: [Int64]) async throws {
        _ = try await dbQueue.write { db in
            let collection = playlist
            try collection.insert(db)
            try Self.writeMembership(orderedStationIds, forCollection: playlist.id.uuidString, at: Date(), in: db)
        }
    }

    /// Metadata and membership together: renaming in its own transaction would leave the
    /// new name persisted and visible when the membership write then failed.
    func updateStationCollection(
        playlistId: UUID,
        name: String,
        orderedStationIds: [Int64]
    ) async throws {
        _ = try await dbQueue.write { db in
            let pid = playlistId.uuidString
            guard var playlist = try Playlist.filter(Playlist.Columns.id == pid).fetchOne(db) else {
                throw StationCollectionError.notFound
            }

            let now = Date()
            playlist.name = name
            playlist.dateModified = now
            try playlist.update(db)

            // In the same transaction, as regular playlist metadata updates do: otherwise a
            // pinned collection shows the new name until relaunch restores the old one.
            try Self.updatePinnedPlaylistName(playlistID: pid, name: name, in: db)

            try Self.writeMembership(orderedStationIds, forCollection: pid, at: now, in: db)
        }
    }

    private static func writeMembership(
        _ orderedStationIds: [Int64],
        forCollection pid: String,
        at now: Date,
        in db: Database
    ) throws {
        try PlaylistStation.filter(PlaylistStation.Columns.playlistId == pid).deleteAll(db)

        var seen = Set<Int64>()
        var position = 0
        for stationId in orderedStationIds where seen.insert(stationId).inserted {
            try PlaylistStation(
                playlistId: pid, stationId: stationId, position: position, dateAdded: now
            ).insert(db)
            position += 1
        }
    }

    /// Read and write in one transaction: two quick membership edits would otherwise both
    /// act on the same snapshot, and the later rewrite would drop the earlier one.
    func addStations(_ stationIds: [Int64], toCollection playlistId: UUID) async throws {
        _ = try await dbQueue.write { db in
            let pid = playlistId.uuidString
            let existing = Set(
                try PlaylistStation
                    .select(PlaylistStation.Columns.stationId, as: Int64.self)
                    .filter(PlaylistStation.Columns.playlistId == pid)
                    .fetchAll(db)
            )
            var position = try PlaylistStation
                .select(max(PlaylistStation.Columns.position), as: Int.self)
                .filter(PlaylistStation.Columns.playlistId == pid)
                .fetchOne(db) ?? -1

            let now = Date()
            for stationId in stationIds where !existing.contains(stationId) {
                position += 1
                try PlaylistStation(
                    playlistId: pid, stationId: stationId, position: position, dateAdded: now
                ).insert(db)
            }

            try Playlist
                .filter(Playlist.Columns.id == pid)
                .updateAll(db, Playlist.Columns.dateModified.set(to: now))
        }
    }

    /// Leaves gaps in `position`; only the relative order matters.
    func removeStations(_ stationIds: [Int64], fromCollection playlistId: UUID) async throws {
        _ = try await dbQueue.write { db in
            let pid = playlistId.uuidString
            try PlaylistStation
                .filter(PlaylistStation.Columns.playlistId == pid)
                .filter(stationIds.contains(PlaylistStation.Columns.stationId))
                .deleteAll(db)

            try Playlist
                .filter(Playlist.Columns.id == pid)
                .updateAll(db, Playlist.Columns.dateModified.set(to: Date()))
        }
    }

    func getStationCollectionCounts() -> [UUID: Int] {
        do {
            return try dbQueue.read { db in
                let rows = try PlaylistStation
                    .select(
                        PlaylistStation.Columns.playlistId,
                        count(PlaylistStation.Columns.stationId).forKey("station_count")
                    )
                    .group(PlaylistStation.Columns.playlistId)
                    .asRequest(of: Row.self)
                    .fetchAll(db)
                return rows.reduce(into: [UUID: Int]()) { counts, row in
                    guard let idString: String = row["playlist_id"], let id = UUID(uuidString: idString) else { return }
                    counts[id] = row["station_count"]
                }
            }
        } catch {
            Logger.error("Failed to load station collection counts: \(error)")
            return [:]
        }
    }
}
