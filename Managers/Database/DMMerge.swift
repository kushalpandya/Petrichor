//
// DatabaseManager extension: manual merging of duplicate entities.
//
// Artists, album artists and composers share the `artists` table (distinguished by
// `track_artists.role`), so one engine covers all three; albums have their own. Merges
// are group-only: they rewrite normalized relationships and record an alias (old name to
// canonical) so a merge survives re-ingestion, but never touch the raw tag strings. The
// album engine is the exception, rewriting `tracks.album` because the Library sidebar
// matches albums by that string column.
//

import Foundation
import GRDB

enum EntityMergeError: LocalizedError {
    case entityNotFound(String)

    var errorDescription: String? {
        switch self {
        case .entityNotFound(let name):
            return "Could not find the entity to merge: \(name)"
        }
    }
}

extension DatabaseManager {
    struct EntityMergeResult {
        let mergedCount: Int
        let canonicalName: String
    }

    // MARK: - Artist Merge (artists / album artists / composers)

    @discardableResult
    func mergeArtists(winnerName: String, loserNames: [String], newName: String?) async throws -> EntityMergeResult {
        try await dbQueue.write { db in
            try self.mergeArtists(winnerName: winnerName, loserNames: loserNames, newName: newName, in: db)
        }
    }

    @discardableResult
    func mergeArtists(winnerName: String, loserNames: [String], newName: String?, in db: Database) throws -> EntityMergeResult {
        guard let winner = try artistRow(named: winnerName, in: db), let winnerId = winner.id else {
            throw EntityMergeError.entityNotFound(winnerName)
        }

        let unknownPlaceholders: Set<String> = [
            LibraryFilterType.artists.unknownPlaceholder,
            LibraryFilterType.albumArtists.unknownPlaceholder,
            LibraryFilterType.composers.unknownPlaceholder
        ]
        var loserIds: [Int64] = []
        var loserAliases: [(normalized: String, display: String)] = []
        for name in loserNames where !unknownPlaceholders.contains(name) {
            guard let row = try artistRow(named: name, in: db), let id = row.id,
                  id != winnerId, !loserIds.contains(id) else { continue }
            loserIds.append(id)
            loserAliases.append((row.normalizedName, row.name))
        }

        // Renaming into an existing artist would violate the unique normalized_name index, so fold it in.
        let trimmedNew = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let renameTarget: String? = (trimmedNew?.isEmpty == false && trimmedNew != winner.name) ? trimmedNew : nil
        let newNormalized = renameTarget.map { ArtistParser.normalizeArtistName($0) }
        if let newNormalized, newNormalized != winner.normalizedName,
           let collide = try Artist.filter(Artist.Columns.normalizedName == newNormalized).fetchOne(db),
           let collideId = collide.id, collideId != winnerId, !loserIds.contains(collideId) {
            loserIds.append(collideId)
            loserAliases.append((collide.normalizedName, collide.name))
        }

        guard !loserIds.isEmpty || renameTarget != nil else {
            return EntityMergeResult(mergedCount: 0, canonicalName: winner.name)
        }

        if !loserIds.isEmpty {
            let marks = databaseQuestionMarks(count: loserIds.count)
            let winnerThenLosers = StatementArguments([winnerId] + loserIds)

            // OR IGNORE sidesteps composite-PK collisions; the DELETE clears the ignored loser rows.
            try db.execute(sql: "UPDATE OR IGNORE track_artists SET artist_id = ? WHERE artist_id IN (\(marks))", arguments: winnerThenLosers)
            try TrackArtist.filter(loserIds.contains(TrackArtist.Columns.artistId)).deleteAll(db)
            try db.execute(sql: "UPDATE OR IGNORE album_artists SET artist_id = ? WHERE artist_id IN (\(marks))", arguments: winnerThenLosers)
            try AlbumArtist.filter(loserIds.contains(AlbumArtist.Columns.artistId)).deleteAll(db)

            try carryOverArtistMetadata(winnerId: winnerId, loserIds: loserIds, in: db)

            // Redirect aliases that pointed at a loser to keep chains flat.
            try ArtistAlias
                .filter(loserIds.contains(ArtistAlias.Columns.canonicalArtistId))
                .updateAll(db, ArtistAlias.Columns.canonicalArtistId.set(to: winnerId))

            for alias in loserAliases {
                try writeArtistAlias(normalized: alias.normalized, display: alias.display, canonicalId: winnerId, in: db)
            }

            try Artist.filter(loserIds.contains(Artist.Columns.id)).deleteAll(db)
        }

        if let renameTarget, let newNormalized {
            if newNormalized != winner.normalizedName {
                // Keep the winner's old name resolvable on future ingests.
                try writeArtistAlias(normalized: winner.normalizedName, display: winner.name, canonicalId: winnerId, in: db)
                try ArtistAlias.filter(ArtistAlias.Columns.normalizedAlias == newNormalized).deleteAll(db)
            }
            try Artist.filter(Artist.Columns.id == winnerId).updateAll(
                db,
                Artist.Columns.name.set(to: renameTarget),
                Artist.Columns.normalizedName.set(to: newNormalized),
                Artist.Columns.sortName.set(to: renameTarget),
                Artist.Columns.updatedAt.set(to: Date())
            )
        }

        try reconcileArtistPins(loserNames: loserAliases.map { $0.display }, oldName: winner.name, newName: renameTarget, in: db)
        try updateArtistStats(in: db)

        return EntityMergeResult(mergedCount: loserIds.count, canonicalName: renameTarget ?? winner.name)
    }

    // MARK: - Album Merge

    @discardableResult
    func mergeAlbums(winnerId: Int64, loserIds: [Int64], newTitle: String?) async throws -> EntityMergeResult {
        try await dbQueue.write { db in
            try self.mergeAlbums(winnerId: winnerId, loserIds: loserIds, newTitle: newTitle, in: db)
        }
    }

    @discardableResult
    func mergeAlbums(winnerId: Int64, loserIds rawLoserIds: [Int64], newTitle: String?, in db: Database) throws -> EntityMergeResult {
        guard let winner = try Album.fetchOne(db, key: winnerId) else {
            throw EntityMergeError.entityNotFound("album #\(winnerId)")
        }

        let loserIds = Array(Set(rawLoserIds.filter { $0 != winnerId }))
        let trimmed = newTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let renameTarget: String? = (trimmed?.isEmpty == false && trimmed != winner.title) ? trimmed : nil
        let canonicalTitle = renameTarget ?? winner.title

        guard !loserIds.isEmpty || renameTarget != nil else {
            return EntityMergeResult(mergedCount: 0, canonicalName: winner.title)
        }

        var loserTitles: [String] = []
        if !loserIds.isEmpty {
            // Capture alias keys before deletes remove the album_artists rows they read.
            var loserAliasKeys: [(key: String, title: String)] = []
            let losers = try Album.filter(loserIds.contains(Album.Columns.id)).fetchAll(db)
            loserTitles = losers.map { $0.title }
            for loser in losers {
                guard let id = loser.id else { continue }
                let normalizedArtist = try albumPrimaryArtistNormalized(albumId: id, in: db)
                loserAliasKeys.append((ScanLookupCache.albumKey(loser.normalizedTitle, normalizedArtist), loser.title))
            }

            let marks = databaseQuestionMarks(count: loserIds.count)
            let winnerThenLosers = StatementArguments([winnerId] + loserIds)

            try Track.filter(loserIds.contains(Track.Columns.albumId)).updateAll(db, Track.Columns.albumId.set(to: winnerId))
            // OR IGNORE sidesteps composite-PK collisions; the DELETE clears the ignored loser rows.
            try db.execute(sql: "UPDATE OR IGNORE album_artists SET album_id = ? WHERE album_id IN (\(marks))", arguments: winnerThenLosers)
            try AlbumArtist.filter(loserIds.contains(AlbumArtist.Columns.albumId)).deleteAll(db)

            if winner.artworkData == nil, let donor = losers.first(where: { $0.artworkData != nil }) {
                winner.artworkData = donor.artworkData
                try winner.update(db)
            }

            try AlbumAlias
                .filter(loserIds.contains(AlbumAlias.Columns.canonicalAlbumId))
                .updateAll(db, AlbumAlias.Columns.canonicalAlbumId.set(to: winnerId))
            for alias in loserAliasKeys {
                try writeAlbumAlias(key: alias.key, displayTitle: alias.title, canonicalId: winnerId, in: db)
            }

            try Album.filter(loserIds.contains(Album.Columns.id)).deleteAll(db)
        }

        // Unify tracks.album so the string-based Library sidebar groups them together.
        try Track.filter(Track.Columns.albumId == winnerId).updateAll(db, Track.Columns.album.set(to: canonicalTitle))

        if let renameTarget {
            let newNormalized = Album.normalizeTitle(renameTarget)
            let oldArtist = try albumPrimaryArtistNormalized(albumId: winnerId, in: db)
            try writeAlbumAlias(
                key: ScanLookupCache.albumKey(winner.normalizedTitle, oldArtist),
                displayTitle: winner.title,
                canonicalId: winnerId,
                in: db
            )
            try AlbumAlias
                .filter(AlbumAlias.Columns.normalizedKey == ScanLookupCache.albumKey(newNormalized, oldArtist))
                .deleteAll(db)
            try Album.filter(Album.Columns.id == winnerId).updateAll(
                db,
                Album.Columns.title.set(to: renameTarget),
                Album.Columns.normalizedTitle.set(to: newNormalized),
                Album.Columns.sortTitle.set(to: renameTarget),
                Album.Columns.updatedAt.set(to: Date())
            )
        }

        try reconcileAlbumPins(loserIds: loserIds, loserTitles: loserTitles, winnerId: winnerId, newTitle: renameTarget, in: db)
        try updateAlbumStats(in: db)

        return EntityMergeResult(mergedCount: loserIds.count, canonicalName: canonicalTitle)
    }

    // MARK: - Helpers

    /// Resolve an artist by display name or normalized name (mirrors the ingestion lookup).
    private func artistRow(named name: String, in db: Database) throws -> Artist? {
        let normalized = ArtistParser.normalizeArtistName(name)
        return try Artist
            .filter((Artist.Columns.name == name) || (Artist.Columns.normalizedName == normalized))
            .fetchOne(db)
    }

    private func albumPrimaryArtistNormalized(albumId: Int64, in db: Database) throws -> String? {
        let sql = """
            SELECT artists.normalized_name AS n
            FROM album_artists
            JOIN artists ON artists.id = album_artists.artist_id
            WHERE album_artists.album_id = ? AND album_artists.role = 'primary'
            ORDER BY album_artists.position
            LIMIT 1
            """
        return try Row.fetchOne(db, sql: sql, arguments: [albumId])?["n"]
    }

    private func carryOverArtistMetadata(winnerId: Int64, loserIds: [Int64], in db: Database) throws {
        guard let winner = try Artist.fetchOne(db, key: winnerId) else { return }
        let losers = try Artist.filter(loserIds.contains(Artist.Columns.id)).fetchAll(db)

        var changed = false
        if winner.artworkData == nil, let donor = losers.first(where: { $0.artworkData != nil }) {
            winner.artworkData = donor.artworkData
            changed = true
        }
        if winner.imageUrl == nil, let donor = losers.first(where: { $0.imageUrl != nil }) {
            winner.imageUrl = donor.imageUrl
            winner.imageSource = donor.imageSource
            winner.imageUpdatedAt = donor.imageUpdatedAt
            changed = true
        }
        if winner.bio == nil, let donor = losers.first(where: { $0.bio != nil }) {
            winner.bio = donor.bio
            winner.bioSource = donor.bioSource
            winner.bioUpdatedAt = donor.bioUpdatedAt
            changed = true
        }
        if changed { try winner.update(db) }
    }

    private func writeArtistAlias(normalized: String, display: String, canonicalId: Int64, in db: Database) throws {
        try ArtistAlias(normalizedAlias: normalized, displayName: display, canonicalArtistId: canonicalId).insert(db)
    }

    private func writeAlbumAlias(key: String, displayTitle: String, canonicalId: Int64, in db: Database) throws {
        try AlbumAlias(normalizedKey: key, displayTitle: displayTitle, canonicalAlbumId: canonicalId).insert(db)
    }

    private func reconcileArtistPins(loserNames: [String], oldName: String, newName: String?, in db: Database) throws {
        let isLibraryItem = PinnedItem.Columns.itemType == PinnedItem.ItemType.library.rawValue
        let artistTypes = [
            LibraryFilterType.artists.rawValue,
            LibraryFilterType.albumArtists.rawValue,
            LibraryFilterType.composers.rawValue
        ]
        if !loserNames.isEmpty {
            try PinnedItem
                .filter(isLibraryItem)
                .filter(artistTypes.contains(PinnedItem.Columns.filterType))
                .filter(loserNames.contains(PinnedItem.Columns.filterValue))
                .deleteAll(db)
        }
        if let newName, newName != oldName {
            try PinnedItem
                .filter(isLibraryItem)
                .filter(artistTypes.contains(PinnedItem.Columns.filterType))
                .filter(PinnedItem.Columns.filterValue == oldName)
                .updateAll(db, PinnedItem.Columns.filterValue.set(to: newName), PinnedItem.Columns.displayName.set(to: newName))
        }
    }

    private func reconcileAlbumPins(loserIds: [Int64], loserTitles: [String], winnerId: Int64, newTitle: String?, in db: Database) throws {
        let isLibraryItem = PinnedItem.Columns.itemType == PinnedItem.ItemType.library.rawValue

        // Precise: pins that reference a loser album by id.
        if !loserIds.isEmpty {
            try PinnedItem.filter(loserIds.contains(PinnedItem.Columns.albumId)).deleteAll(db)
        }

        // Legacy title-only pins (nil albumId): only remove when no album with that title
        // survives, so a pin meant for an unrelated same-title album is never deleted.
        for title in Set(loserTitles) where try Album.filter(Album.Columns.title == title).fetchCount(db) == 0 {
            try PinnedItem
                .filter(isLibraryItem)
                .filter(PinnedItem.Columns.filterType == LibraryFilterType.albums.rawValue)
                .filter(PinnedItem.Columns.albumId == nil)
                .filter(PinnedItem.Columns.filterValue == title)
                .deleteAll(db)
        }

        if let newTitle {
            try PinnedItem
                .filter(isLibraryItem)
                .filter(PinnedItem.Columns.albumId == winnerId)
                .updateAll(db, PinnedItem.Columns.filterValue.set(to: newTitle), PinnedItem.Columns.displayName.set(to: newTitle))
        }
    }

    // MARK: - Merge Candidates

    /// A selectable album in the merge sheet. Albums must be identified by id since titles
    /// are not unique, unlike artist-type entities keyed by their unique name.
    struct AlbumMergeCandidate: Identifiable {
        let id: Int64
        let title: String
        let artistName: String?
        let trackCount: Int
    }

    func getAlbumMergeCandidates() -> [AlbumMergeCandidate] {
        do {
            return try dbQueue.read { db in
                // Raw SQL: the primary-album-artist correlated subquery doesn't map cleanly
                // to GRDB's query interface (mirrors getAlbumEntities).
                let sql = """
                    SELECT
                        albums.id AS id,
                        albums.title AS title,
                        albums.total_tracks AS track_count,
                        (SELECT artists.name
                         FROM album_artists
                         JOIN artists ON artists.id = album_artists.artist_id
                         WHERE album_artists.album_id = albums.id AND album_artists.role = 'primary'
                         ORDER BY album_artists.position
                         LIMIT 1) AS artist_name
                    FROM albums
                    WHERE albums.total_tracks > 0
                    ORDER BY albums.sort_title COLLATE NOCASE
                    """
                return try Row.fetchAll(db, sql: sql).compactMap { row in
                    guard let id = row["id"] as Int64? else { return nil }
                    return AlbumMergeCandidate(
                        id: id,
                        title: row["title"] as String? ?? "",
                        artistName: row["artist_name"] as String?,
                        trackCount: (row["track_count"] as Int?) ?? 0
                    )
                }
            }
        } catch {
            Logger.error("Failed to get album merge candidates: \(error)")
            return []
        }
    }
}
