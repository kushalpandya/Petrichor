//
// DatabaseManager class extension
//
// This extension contains background migration logic for heavy one-time data transformations
// that run asynchronously after app launch without blocking the UI.
//

import Foundation
import GRDB

extension DatabaseManager {
    func runPendingBackgroundMigrations() async {
        let pending: [(identifier: String, progress: String?)]
        do {
            pending = try await dbQueue.read { db -> [(String, String?)] in
                if try db.tableExists("background_migrations") {
                    let sql = """
                        SELECT identifier, progress FROM background_migrations \
                        WHERE completed_at IS NULL ORDER BY identifier
                        """
                    return try Row.fetchAll(db, sql: sql)
                        .map { ($0["identifier"], $0["progress"]) }
                }
                return []
            }
        } catch {
            Logger.error("Failed to read pending background migrations: \(error)")
            return
        }
        if pending.isEmpty { return }

        // Skip migrations on a fresh/empty database — nothing to migrate
        let trackCount = (try? await dbQueue.read { db in try Track.fetchCount(db) }) ?? 0
        if trackCount == 0 {
            for (identifier, _) in pending {
                completeBackgroundMigration(identifier)
            }
            Logger.info("Skipped \(pending.count) background migrations on empty database")
            return
        }

        for (identifier, progress) in pending {
            switch identifier {
            case "v8_background_convert_artwork_to_heic":
                await convertArtworkToHEIC(progress: progress)
            case Self.knownArtistsMigrationIdentifier:
                await loadKnownArtistsAndRebuild(progress: progress)
            default:
                Logger.warning("Unknown background migration: \(identifier)")
            }
        }
    }

    // MARK: - v8: Convert Artwork to HEIC

    private struct ArtworkConversionProgress: Codable {
        let table: String
        let offset: Int
    }

    private struct ArtworkTableOps: Sendable {
        let name: String
        let count: @Sendable (Database) throws -> Int
        let fetchBatch: @Sendable (Database, Int, Int) throws -> [Row]
        let compressAndUpdate: @Sendable (DatabaseQueue, [Row]) throws -> Int
    }

    private static let artworkMigrationIdentifier = "v8_background_convert_artwork_to_heic"

    private static let artworkTableOps: [ArtworkTableOps] = [
        ArtworkTableOps(
            name: "albums",
            count: { db in try Album.filter(Album.Columns.artworkData != nil).fetchCount(db) },
            fetchBatch: { db, limit, offset in
                try Row.fetchAll(db, Album
                    .filter(Album.Columns.artworkData != nil)
                    .select(Album.Columns.id, Album.Columns.title, Album.Columns.artworkData)
                    .limit(limit, offset: offset))
            },
            compressAndUpdate: { dbQueue, rows in
                var updates: [(Int64, Data)] = []
                for row in rows {
                    guard let rowId: Int64 = row[Album.Columns.id],
                          let original: Data = row[Album.Columns.artworkData] else { continue }
                    let name: String? = row[Album.Columns.title]
                    guard let compressed = ImageUtils.compressImage(
                        from: original, source: "album: \(name ?? "id=\(rowId)")"
                    ) else { continue }
                    guard compressed.count < original.count else { continue }
                    updates.append((rowId, compressed))
                }
                try dbQueue.write { db in
                    for (rowId, data) in updates {
                        try Album.filter(Album.Columns.id == rowId)
                            .updateAll(db, Album.Columns.artworkData.set(to: data))
                    }
                }
                return updates.count
            }
        ),
        ArtworkTableOps(
            name: "artists",
            count: { db in try Artist.filter(Artist.Columns.artworkData != nil).fetchCount(db) },
            fetchBatch: { db, limit, offset in
                try Row.fetchAll(db, Artist
                    .filter(Artist.Columns.artworkData != nil)
                    .select(Artist.Columns.id, Artist.Columns.name, Artist.Columns.artworkData)
                    .limit(limit, offset: offset))
            },
            compressAndUpdate: { dbQueue, rows in
                var updates: [(Int64, Data)] = []
                for row in rows {
                    guard let rowId: Int64 = row[Artist.Columns.id],
                          let original: Data = row[Artist.Columns.artworkData] else { continue }
                    let name: String? = row[Artist.Columns.name]
                    guard let compressed = ImageUtils.compressImage(
                        from: original, source: "artist: \(name ?? "id=\(rowId)")"
                    ) else { continue }
                    guard compressed.count < original.count else { continue }
                    updates.append((rowId, compressed))
                }
                try dbQueue.write { db in
                    for (rowId, data) in updates {
                        try Artist.filter(Artist.Columns.id == rowId)
                            .updateAll(db, Artist.Columns.artworkData.set(to: data))
                    }
                }
                return updates.count
            }
        ),
        ArtworkTableOps(
            name: "tracks",
            count: { db in try FullTrack.filter(FullTrack.Columns.trackArtworkData != nil).fetchCount(db) },
            fetchBatch: { db, limit, offset in
                try Row.fetchAll(db, FullTrack
                    .filter(FullTrack.Columns.trackArtworkData != nil)
                    .select(FullTrack.Columns.trackId, FullTrack.Columns.filename, FullTrack.Columns.trackArtworkData)
                    .limit(limit, offset: offset))
            },
            compressAndUpdate: { dbQueue, rows in
                var updates: [(Int64, Data)] = []
                for row in rows {
                    guard let rowId: Int64 = row[FullTrack.Columns.trackId],
                          let original: Data = row[FullTrack.Columns.trackArtworkData] else { continue }
                    let name: String? = row[FullTrack.Columns.filename]
                    guard let compressed = ImageUtils.compressImage(
                        from: original, source: "track: \(name ?? "id=\(rowId)")"
                    ) else { continue }
                    guard compressed.count < original.count else { continue }
                    updates.append((rowId, compressed))
                }
                try dbQueue.write { db in
                    for (rowId, data) in updates {
                        try FullTrack.filter(FullTrack.Columns.trackId == rowId)
                            .updateAll(db, FullTrack.Columns.trackArtworkData.set(to: data))
                    }
                }
                return updates.count
            }
        ),
        ArtworkTableOps(
            name: "playlists",
            count: { db in try Playlist.filter(Playlist.Columns.coverArtworkData != nil).fetchCount(db) },
            fetchBatch: { db, limit, offset in
                try Row.fetchAll(db, Playlist
                    .filter(Playlist.Columns.coverArtworkData != nil)
                    .select(Playlist.Columns.id, Playlist.Columns.name, Playlist.Columns.coverArtworkData)
                    .limit(limit, offset: offset))
            },
            compressAndUpdate: { dbQueue, rows in
                var updates: [(String, Data)] = []
                for row in rows {
                    guard let rowId: String = row[Playlist.Columns.id],
                          let original: Data = row[Playlist.Columns.coverArtworkData] else { continue }
                    let name: String? = row[Playlist.Columns.name]
                    guard let compressed = ImageUtils.compressImage(
                        from: original, source: "playlist: \(name ?? "id=\(rowId)")"
                    ) else { continue }
                    guard compressed.count < original.count else { continue }
                    updates.append((rowId, compressed))
                }
                try dbQueue.write { db in
                    for (rowId, data) in updates {
                        try Playlist.filter(Playlist.Columns.id == rowId)
                            .updateAll(db, Playlist.Columns.coverArtworkData.set(to: data))
                    }
                }
                return updates.count
            }
        )
    ]

    private func convertArtworkToHEIC(progress: String?) async {
        NotificationManager.shared.startActivity("Optimizing Library...")

        let sizeBefore = getDatabaseSize() ?? 0
        let batchSize = 50
        let tables = Self.artworkTableOps

        var resumeTable = tables[0].name
        var resumeOffset = 0
        if let progress = progress,
           let data = progress.data(using: .utf8),
           let state = try? JSONDecoder().decode(ArtworkConversionProgress.self, from: data) {
            resumeTable = state.table
            resumeOffset = state.offset
            Logger.info("Resuming artwork optimization from \(resumeTable) at offset \(resumeOffset)")
        }

        let startIndex = tables.firstIndex { $0.name == resumeTable } ?? 0

        do {
            let totalRows = try await dbQueue.read { db -> Int in
                try tables.reduce(0) { total, table in try total + table.count(db) }
            }

            Logger.info("Starting artwork optimization: \(totalRows) total rows")

            try await Task.detached(priority: .utility) { [dbQueue, weak self] in
                guard let self = self else { return }

                var totalProcessed = 0
                if startIndex > 0 || resumeOffset > 0 {
                    totalProcessed = try dbQueue.read { db -> Int in
                        var processed = 0
                        for tableIdx in 0..<startIndex {
                            processed += try tables[tableIdx].count(db)
                        }
                        return processed + resumeOffset
                    }
                    NotificationManager.shared.updateActivityProgress(current: totalProcessed, total: totalRows)
                }

                for tableIndex in startIndex..<tables.count {
                    let ops = tables[tableIndex]
                    var offset = (tableIndex == startIndex) ? resumeOffset : 0
                    var converted = 0
                    var skipped = 0

                    while true {
                        let rows = try dbQueue.read { db in try ops.fetchBatch(db, batchSize, offset) }
                        if rows.isEmpty { break }

                        let batchConverted = try ops.compressAndUpdate(dbQueue, rows)
                        converted += batchConverted
                        skipped += rows.count - batchConverted
                        totalProcessed += rows.count
                        offset += batchSize

                        NotificationManager.shared.updateActivityProgress(current: totalProcessed, total: totalRows)
                        if let progressData = try? JSONEncoder().encode(
                            ArtworkConversionProgress(table: ops.name, offset: offset)
                        ),
                           let progressJson = String(data: progressData, encoding: .utf8) {
                            self.updateMigrationProgress(Self.artworkMigrationIdentifier, progress: progressJson)
                        }
                    }

                    let skipInfo = skipped > 0 ? " (\(skipped) skipped)" : ""
                    Logger.info("Optimized \(converted) \(ops.name) artworks\(skipInfo)")
                }
            }.value

            try await vacuumDatabase()
            completeBackgroundMigration(Self.artworkMigrationIdentifier)

            let sizeAfter = getDatabaseSize() ?? 0
            let spaceSaved = max(0, sizeBefore - sizeAfter)

            NotificationManager.shared.stopActivity()
            if spaceSaved > 0 {
                let savedMB = Double(spaceSaved) / (1024.0 * 1024.0)
                NotificationManager.shared.addMessage(.info, "Library optimized - reclaimed \(String(format: "%.1f", savedMB)) MB")
            } else {
                NotificationManager.shared.addMessage(.info, "Library optimized")
            }
            Logger.info("Artwork optimization completed")
        } catch {
            NotificationManager.shared.stopActivity()
            NotificationManager.shared.addMessage(.error, "Failed to optimize library")
            Logger.error("Artwork optimization failed: \(error)")
        }
    }

    // MARK: - v9: Load Known Artists & Rebuild Artist Associations

    private static let knownArtistsMigrationIdentifier = "v9_background_rebuild_artist_associations"

    private struct KnownArtistsProgress: Codable {
        let offset: Int
    }

    private func loadKnownArtistsAndRebuild(progress: String?) async {
        NotificationManager.shared.startActivity("Updating Artists...")

        var resumeOffset = 0
        if let progress = progress,
           let data = progress.data(using: .utf8),
           let state = try? JSONDecoder().decode(KnownArtistsProgress.self, from: data) {
            resumeOffset = state.offset
            Logger.info("Resuming known artists migration at offset \(resumeOffset)")
        }

        do {
            try await rebuildArtistAssociations(resumeOffset: resumeOffset)

            completeBackgroundMigration(Self.knownArtistsMigrationIdentifier)
            NotificationManager.shared.stopActivity()
            NotificationManager.shared.addMessage(.info, "Artists information updated successfully")
            Logger.info("Known artists migration completed")
        } catch {
            NotificationManager.shared.stopActivity()
            NotificationManager.shared.addMessage(.error, "Failed to update artists information")
            Logger.error("Known artists migration failed: \(error)")
        }
    }

    /// Rebuild all TrackArtist/AlbumArtist associations using updated parser
    private func rebuildArtistAssociations(resumeOffset: Int) async throws {
        let totalTracks = try await dbQueue.read { db in
            try FullTrack.filter(FullTrack.Columns.isDuplicate == false).fetchCount(db)
        }

        guard totalTracks > 0 else {
            Logger.info("No tracks to rebuild artist associations for")
            return
        }

        Logger.info("Rebuilding artist associations for \(totalTracks) tracks")

        try await Task.detached(priority: .utility) { [dbQueue, weak self] in
            guard let self = self else { return }

            // Snapshot pinned items before clearing associations
            let pinnedArtists = self.snapshotPinnedItems(idColumn: PinnedItem.Columns.artistId)
            let pinnedAlbums = self.snapshotPinnedItems(idColumn: PinnedItem.Columns.albumId)

            ArtistParser.loadKnownArtists()

            // Clear existing associations and reset stats
            _ = try dbQueue.write { db in
                try TrackArtist.deleteAll(db)
                try AlbumArtist.deleteAll(db)
                try Artist.updateAll(db, Artist.Columns.totalTracks.set(to: 0), Artist.Columns.totalAlbums.set(to: 0))
                try Album.updateAll(db, Album.Columns.totalTracks.set(to: 0))
            }

            Logger.info("Cleared existing artist/album associations")

            // Rebuild in batches
            let batchSize = 500
            var offset = resumeOffset

            while offset < totalTracks {
                let tracks = try dbQueue.read { db in
                    try FullTrack
                        .filter(FullTrack.Columns.isDuplicate == false)
                        .order(FullTrack.Columns.trackId)
                        .limit(batchSize, offset: offset)
                        .fetchAll(db)
                }

                if tracks.isEmpty { break }

                _ = try dbQueue.write { db in
                    for var track in tracks {
                        try self.processTrackArtists(track, in: db)
                        try self.processTrackAlbum(&track, in: db)
                    }
                }

                offset += tracks.count
                NotificationManager.shared.updateActivityProgress(current: offset, total: totalTracks)
                self.saveProgress(offset: offset)
            }

            // Update stats
            try dbQueue.write { db in
                try self.updateEntityStats(in: db)
            }

            // Re-link pinned items by name
            self.relinkPinnedArtists(pinnedArtists)
            self.relinkPinnedAlbums(pinnedAlbums)

            ArtistParser.unloadKnownArtists()
            Logger.info("Artist associations rebuild completed")
        }.value

        // Clean up orphaned entities (runs in its own dbQueue.write)
        try await cleanupOrphanedData()
    }

    // MARK: - v9 Helpers

    private func saveProgress(offset: Int) {
        if let data = try? JSONEncoder().encode(KnownArtistsProgress(offset: offset)),
           let json = String(data: data, encoding: .utf8) {
            updateMigrationProgress(Self.knownArtistsMigrationIdentifier, progress: json)
        }
    }

    private func snapshotPinnedItems(idColumn: Column) -> [(id: Int64, name: String)] {
        (try? dbQueue.read { db in
            try PinnedItem
                .filter(idColumn != nil)
                .filter(PinnedItem.Columns.filterValue != nil)
                .select(PinnedItem.Columns.id, PinnedItem.Columns.filterValue)
                .asRequest(of: Row.self)
                .fetchAll(db)
                .compactMap { row -> (Int64, String)? in
                    guard let id: Int64 = row[PinnedItem.Columns.id],
                          let name: String = row[PinnedItem.Columns.filterValue] else { return nil }
                    return (id, name)
                }
        }) ?? []
    }

    private func relinkPinnedArtists(_ pinnedArtists: [(id: Int64, name: String)]) {
        guard !pinnedArtists.isEmpty else { return }
        do {
            _ = try dbQueue.write { db in
                for (pinnedId, artistName) in pinnedArtists {
                    let normalized = ArtistParser.normalizeArtistName(artistName)
                    if let artist = try Artist.filter(Artist.Columns.normalizedName == normalized).fetchOne(db),
                       let newId = artist.id {
                        try PinnedItem.filter(PinnedItem.Columns.id == pinnedId)
                            .updateAll(db, PinnedItem.Columns.artistId.set(to: newId))
                    }
                }
            }
            Logger.info("Re-linked \(pinnedArtists.count) pinned artist items")
        } catch {
            Logger.error("Failed to re-link pinned artists: \(error)")
        }
    }

    private func relinkPinnedAlbums(_ pinnedAlbums: [(id: Int64, name: String)]) {
        guard !pinnedAlbums.isEmpty else { return }
        do {
            _ = try dbQueue.write { db in
                for (pinnedId, albumName) in pinnedAlbums {
                    let normalizedTitle = Album.normalizeTitle(albumName)
                    if let album = try Album.filter(Album.Columns.normalizedTitle == normalizedTitle).fetchOne(db),
                       let newId = album.id {
                        try PinnedItem.filter(PinnedItem.Columns.id == pinnedId)
                            .updateAll(db, PinnedItem.Columns.albumId.set(to: newId))
                    }
                }
            }
            Logger.info("Re-linked \(pinnedAlbums.count) pinned album items")
        } catch {
            Logger.error("Failed to re-link pinned albums: \(error)")
        }
    }

    // MARK: - Migration State

    func isActiveBackgroundMigrationResumable() -> Bool {
        do {
            return try dbQueue.read { db -> Bool in
                if try db.tableExists("background_migrations") {
                    return try Bool.fetchOne(
                        db,
                        sql: "SELECT resumable FROM background_migrations WHERE completed_at IS NULL LIMIT 1"
                    ) ?? true
                }
                return true
            }
        } catch {
            return true
        }
    }

    // MARK: - Helpers

    func updateMigrationProgress(_ identifier: String, progress: String) {
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE background_migrations SET progress = ? WHERE identifier = ?",
                    arguments: [progress, identifier]
                )
            }
        } catch {
            Logger.error("Failed to update migration progress for \(identifier): \(error)")
        }
    }

    func completeBackgroundMigration(_ identifier: String) {
        do {
            try dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE background_migrations SET completed_at = ?, progress = NULL WHERE identifier = ?",
                    arguments: [Date(), identifier]
                )
            }
        } catch {
            Logger.error("Failed to mark migration \(identifier) as completed: \(error)")
        }
    }
}
