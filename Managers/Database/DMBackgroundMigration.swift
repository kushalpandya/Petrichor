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

        for (identifier, progress) in pending {
            switch identifier {
            case "v8_background_convert_artwork_to_heic":
                await convertArtworkToHEIC(progress: progress)
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
