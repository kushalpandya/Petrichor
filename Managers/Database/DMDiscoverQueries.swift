//
// DatabaseManager class extension
//
// This extension contains the queries backing the Discover screen: the Featured and
// Recently Played entity carousels, and the Fresh Music track list.
//
// The carousels mix six entity kinds. Each kind is deliberately sourced from the same
// table/column the rest of the app browses it by, so a tile's count and its detail view
// always agree (genres come from the denormalized `tracks.genre`, decades from a
// SUBSTR over `tracks.year`, years from the exact stored value, and so on).
//

import Foundation
import GRDB

// MARK: - Queries

extension DatabaseManager {
    // MARK: - Featured

    /// Candidate entities for the Featured carousel, for one signal, across all six kinds.
    /// Each kind is ranked independently; `LMDiscover` does the mixing.
    func getDiscoverFeaturedCandidates(
        signal: DiscoverSignal,
        limitPerKind: Int = DiscoverConfiguration.carouselItemCount
    ) -> [DiscoverEntityRow] {
        let isImageFetchEnabled = ArtistBioManager.shared.isArtistInfoFetchEnabled
        let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")

        do {
            return try dbQueue.read { db in
                var rows: [DiscoverEntityRow] = []
                rows += try self.featuredAlbums(db: db, signal: signal, hideDuplicates: hideDuplicates, limit: limitPerKind)
                rows += try self.featuredArtists(
                    db: db,
                    signal: signal,
                    hideDuplicates: hideDuplicates,
                    isImageFetchEnabled: isImageFetchEnabled,
                    limit: limitPerKind
                )
                rows += try self.featuredPlaylists(db: db, signal: signal, hideDuplicates: hideDuplicates, limit: limitPerKind)
                rows += try self.featuredDecades(db: db, signal: signal, hideDuplicates: hideDuplicates, limit: limitPerKind)
                rows += try self.featuredYears(db: db, signal: signal, hideDuplicates: hideDuplicates, limit: limitPerKind)
                rows += try self.featuredGenres(db: db, signal: signal, hideDuplicates: hideDuplicates, limit: limitPerKind)
                return rows
            }
        } catch {
            Logger.error("Failed to get discover featured candidates: \(error)")
            return []
        }
    }

    // MARK: - Recently Played

    /// The most recently played track IDs. Every Recently Played candidate is derived from
    /// this pool, including the smart playlists evaluated in Swift.
    func discoverRecentTrackIds(limit: Int = 200) -> [Int64] {
        let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
        do {
            return try dbQueue.read { db in
                let sql = """
                    SELECT t.id AS trackId
                    FROM tracks t
                    WHERE t.play_count > 0
                      AND t.last_played_date IS NOT NULL
                      \(Self.duplicateClause(hideDuplicates, alias: "t"))
                    ORDER BY t.last_played_date DESC
                    LIMIT ?
                """
                return try Int64.fetchAll(db, sql: sql, arguments: [limit])
            }
        } catch {
            Logger.error("Failed to get discover recent track ids: \(error)")
            return []
        }
    }

    func hasDiscoverEngagementThreshold(_ threshold: Int) -> Bool {
        let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
        do {
            return try dbQueue.read { db in
                var request = Track.filter(
                    Track.Columns.isFavorite == true
                        || (Track.Columns.playCount > 0 && Track.Columns.lastPlayedDate != nil)
                )
                if hideDuplicates {
                    request = request.filter(Track.Columns.isDuplicate == false)
                }
                return try request.limit(threshold).fetchCount(db) >= threshold
            }
        } catch {
            Logger.error("Failed to check Discover engagement threshold: \(error)")
            return false
        }
    }

    /// Candidate entities derived from the most recently played tracks, across all six kinds.
    func getDiscoverRecentlyPlayedCandidates(
        trackIds: [Int64],
        limitPerKind: Int = DiscoverConfiguration.carouselItemCount * 2
    ) -> [DiscoverEntityRow] {
        let isImageFetchEnabled = ArtistBioManager.shared.isArtistInfoFetchEnabled
        let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")

        do {
            return try dbQueue.read { db in
                guard !trackIds.isEmpty else { return [] }

                var rows: [DiscoverEntityRow] = []
                rows += try self.recentAlbums(db: db, trackIds: trackIds, hideDuplicates: hideDuplicates, limit: limitPerKind)
                rows += try self.recentArtists(
                    db: db,
                    trackIds: trackIds,
                    hideDuplicates: hideDuplicates,
                    isImageFetchEnabled: isImageFetchEnabled,
                    limit: limitPerKind
                )
                rows += try self.recentPlaylists(db: db, trackIds: trackIds, hideDuplicates: hideDuplicates, limit: limitPerKind)

                // Category counts come from one grouped pass each rather than a
                // correlated subquery: `SUBSTR(year, ...) = ?` is not sargable, so a
                // per-decade count would rescan the whole table every time.
                let genreCounts = try self.discoverGenreTrackCounts(db: db, hideDuplicates: hideDuplicates)
                let yearCounts = try self.discoverYearTrackCounts(db: db, hideDuplicates: hideDuplicates)
                let decadeCounts = Self.discoverDecadeTrackCounts(from: yearCounts)
                rows += try self.recentDecades(db: db, trackIds: trackIds, counts: decadeCounts, limit: limitPerKind)
                rows += try self.recentYears(db: db, trackIds: trackIds, counts: yearCounts, limit: limitPerKind)
                rows += try self.recentGenres(db: db, trackIds: trackIds, counts: genreCounts, limit: limitPerKind)
                return rows
            }
        } catch {
            Logger.error("Failed to get discover recently played candidates: \(error)")
            return []
        }
    }

    // MARK: - Smart Playlists

    /// Evaluates each smart playlist's criteria once, for the callers below to share.
    ///
    /// Each evaluation is a full track fetch including artwork blobs, so re-running it per
    /// consumer (two signals, the recent row, and the collage warm) is the most expensive
    /// avoidable thing in a Discover load.
    func discoverSmartPlaylistTracks(for playlists: [Playlist]) -> [UUID: [Track]] {
        Dictionary(playlists.map { ($0.id, getTracksForSmartPlaylistSync($0)) }) { first, _ in first }
    }

    /// Auto-updating smart playlists hold no `playlist_tracks` rows (membership is
    /// re-evaluated from `smartCriteria` on demand), so the SQL playlist queries above
    /// structurally miss them. Aggregate the same signals in Swift instead.
    ///
    /// Callers pass only eligible playlists; see `Playlist.isDiscoverEligible`.
    func getDiscoverSmartPlaylistCandidates(
        for playlists: [Playlist],
        tracksByPlaylist: [UUID: [Track]],
        signal: DiscoverSignal
    ) -> [DiscoverEntityRow] {
        playlists.compactMap { playlist in
            let tracks = tracksByPlaylist[playlist.id] ?? []
            guard tracks.count >= 2 else { return nil }

            let hot = tracks.filter { $0.playCount >= DiscoverSignal.hotPlayThreshold }
            let hotPlays = hot.reduce(0) { $0 + $1.playCount }
            let maxPlayCount = tracks.map(\.playCount).max() ?? 0
            // Qualifying tracks only, matching signalSelect: a single first play today
            // must not make an entity's old heavy plays look current.
            let lastPlayed = hot.compactMap(\.lastPlayedDate).max()
            let favoriteTracks = tracks.filter(\.isFavorite).count
            let totalPlays = tracks.reduce(0) { $0 + $1.playCount }

            guard signal.admits(
                hotTracks: hot.count,
                lastPlayed: lastPlayed,
                maxPlayCount: maxPlayCount,
                favoriteTracks: favoriteTracks,
                totalPlays: totalPlays
            ) else {
                return nil
            }

            return DiscoverEntityRow(
                ref: .playlist(id: playlist.id, name: playlist.name),
                trackCount: tracks.count,
                artworkData: nil,
                year: nil,
                artistName: nil,
                lastPlayed: lastPlayed,
                hotPlays: hotPlays,
                favoriteTracks: favoriteTracks,
                totalPlays: totalPlays
            )
        }
    }

    /// Recently Played counterpart for smart playlists, whose membership SQL can't aggregate.
    func getDiscoverRecentSmartPlaylistCandidates(
        for playlists: [Playlist],
        tracksByPlaylist: [UUID: [Track]],
        recentTrackIds: Set<Int64>
    ) -> [DiscoverEntityRow] {
        playlists.compactMap { playlist in
            let tracks = tracksByPlaylist[playlist.id] ?? []
            // Ranked on members inside the pool only, so a playlist whose newest play is
            // older than the pool can't appear alongside genuinely recent entities.
            let recent = tracks.filter { $0.trackId.map(recentTrackIds.contains) ?? false }
            guard let lastPlayed = recent.compactMap(\.lastPlayedDate).max() else { return nil }

            return DiscoverEntityRow(
                ref: .playlist(id: playlist.id, name: playlist.name),
                trackCount: tracks.count,
                artworkData: nil,
                year: nil,
                artistName: nil,
                lastPlayed: lastPlayed
            )
        }
    }

    // MARK: - Sticky Cache Resolution

    /// Re-resolve persisted Featured refs without reselecting them. Refs that no longer
    /// resolve (deleted album, renamed artist, emptied genre) are simply absent from the
    /// result: the row shrinks rather than substituting different tiles.
    func resolveDiscoverEntities(
        _ refs: [DiscoverEntityRef],
        smartPlaylists: [Playlist] = [],
        tracksByPlaylist: [UUID: [Track]] = [:]
    ) -> [DiscoverEntityRef: DiscoverEntityRow] {
        guard !refs.isEmpty else { return [:] }

        let isImageFetchEnabled = ArtistBioManager.shared.isArtistInfoFetchEnabled
        let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")

        var resolved: [DiscoverEntityRef: DiscoverEntityRow] = [:]

        do {
            resolved = try dbQueue.read { db in
                var resolved: [DiscoverEntityRef: DiscoverEntityRow] = [:]

                // `DiscoverEntityRef` hashes on stable identity, so a freshly-resolved ref
                // keys the same entry as the persisted one even after a rename.
                let albumIds = refs.compactMap { $0.kind == .album ? $0.albumId : nil }
                for row in try self.resolveAlbums(db: db, albumIds: albumIds, hideDuplicates: hideDuplicates) {
                    resolved[row.ref] = row
                }

                let artistNames = refs.filter { $0.kind == .artist }.map(\.value)
                let artistIds = refs.compactMap { $0.kind == .artist ? $0.artistId : nil }
                for row in try self.resolveArtists(
                    db: db,
                    ids: artistIds,
                    names: artistNames,
                    hideDuplicates: hideDuplicates,
                    isImageFetchEnabled: isImageFetchEnabled
                ) {
                    resolved[row.ref] = row
                }

                let playlistIds = refs.compactMap { $0.kind == .playlist ? $0.playlistId : nil }
                for row in try self.resolvePlaylists(db: db, playlistIds: playlistIds, hideDuplicates: hideDuplicates) {
                    resolved[row.ref] = row
                }
                let categoryRefs = refs.filter { $0.kind == .genre || $0.kind == .decade || $0.kind == .year }
                if !categoryRefs.isEmpty {
                    let kinds = Set(categoryRefs.map(\.kind))
                    let genreCounts = kinds.contains(.genre)
                        ? try self.discoverGenreTrackCounts(db: db, hideDuplicates: hideDuplicates)
                        : [:]
                    let yearCounts = kinds.contains(.year) || kinds.contains(.decade)
                        ? try self.discoverYearTrackCounts(db: db, hideDuplicates: hideDuplicates)
                        : [:]
                    let decadeCounts = kinds.contains(.decade)
                        ? Self.discoverDecadeTrackCounts(from: yearCounts)
                        : [:]
                    for ref in categoryRefs {
                        let count: Int?
                        switch ref.kind {
                        case .genre: count = genreCounts[ref.value]
                        case .decade: count = decadeCounts[ref.value]
                        case .year: count = yearCounts[ref.value]
                        default: count = nil
                        }
                        guard let count, count > 0 else { continue }
                        resolved[ref] = DiscoverEntityRow(
                            ref: ref, trackCount: count, artworkData: nil, year: nil, artistName: nil
                        )
                    }
                }

                return resolved
            }
        } catch {
            Logger.error("Failed to resolve discover entities: \(error)")
            return [:]
        }

        // Smart playlists hold no playlist_tracks rows, so the query above can't see them.
        // Runs *outside* the read block on purpose: getTracksForSmartPlaylistSync opens its
        // own dbQueue.read, and GRDB database methods are not reentrant.
        let unresolvedSmart = smartPlaylists.filter { playlist in
            refs.contains { $0.kind == .playlist && $0.playlistId == playlist.id }
                && !resolved.keys.contains { $0.playlistId == playlist.id }
        }
        for playlist in unresolvedSmart {
            let tracks = tracksByPlaylist[playlist.id] ?? getTracksForSmartPlaylistSync(playlist)
            guard !tracks.isEmpty else { continue }
            let ref = DiscoverEntityRef.playlist(id: playlist.id, name: playlist.name)
            resolved[ref] = DiscoverEntityRow(
                ref: ref,
                trackCount: tracks.count,
                artworkData: nil,
                year: nil,
                artistName: nil,
                lastPlayed: tracks.compactMap(\.lastPlayedDate).max()
            )
        }

        return resolved
    }

    // MARK: - Fresh Music

    /// Random never-played tracks. Deliberately does *not* pad with least-recently-played
    /// tracks when there aren't enough: padding makes the empty state unreachable.
    func getDiscoverTracks(limit: Int = 50) -> [Track] {
        do {
            return try dbQueue.read { db in
                let query = Track.all()
                    .filter(Track.Columns.isDuplicate == false)
                    .filter(Track.Columns.playCount == 0)

                var tracks = try query
                    .order(sql: "RANDOM()")
                    .limit(limit)
                    .fetchAll(db)

                try populateAlbumArtworkForTracks(&tracks, db: db)

                return tracks
            }
        } catch {
            Logger.error("Failed to get discover tracks: \(error)")
            return []
        }
    }
}

// MARK: - Featured Helpers

private extension DatabaseManager {
    /// The aggregates every Featured query selects, so the two signals share one query shape.
    static let signalSelect = """
        MAX(CASE WHEN t.play_count >= \(DiscoverSignal.hotPlayThreshold) THEN t.last_played_date END) AS lastPlayed,
        SUM(CASE WHEN t.play_count >= \(DiscoverSignal.hotPlayThreshold) THEN t.play_count ELSE 0 END) AS hotPlays,
        SUM(CASE WHEN t.play_count >= \(DiscoverSignal.hotPlayThreshold) THEN 1 ELSE 0 END) AS hotTracks,
        MAX(t.play_count) AS maxPlayCount,
        SUM(t.play_count) AS totalPlays,
        SUM(CASE WHEN t.is_favorite THEN 1 ELSE 0 END) AS favoriteTracks
    """

    /// Qualifying plays, decayed by time since the last one, so an album played 40x two
    /// years ago doesn't outrank one played 6x yesterday. The COALESCE is defensive: an
    /// unparseable stored date scores as "played today" rather than collapsing to NULL.
    /// `prefix` qualifies the aggregate aliases so the same expression can be re-applied
    /// outside a derived table, where they'd otherwise be out of scope.
    static func rotationOrder(prefix: String = "") -> String {
        """
        (CAST(\(prefix)hotPlays AS REAL)
         / (1.0 + MAX(0.0, julianday('now') - COALESCE(julianday(\(prefix)lastPlayed), julianday('now')))
            / \(DiscoverSignal.rotationHalfLifeDays))) DESC
        """
    }

    /// Plays plus starred tracks, weighted. Ranking is per kind, and `selectRoundRobin`
    /// then takes the best of each, so large containers can't crowd out albums even though
    /// they accumulate both terms faster.
    static func lovedOrder(prefix: String = "") -> String {
        "(\(prefix)totalPlays + \(prefix)favoriteTracks * \(DiscoverSignal.favoriteWeight)) DESC"
    }

    func signalOrder(_ signal: DiscoverSignal, prefix: String = "") -> String {
        switch signal {
        case .inRotation: return Self.rotationOrder(prefix: prefix)
        // Safe because the selection is persisted: stable within an update interval.
        case .neglected: return "RANDOM()"
        case .mostLoved: return Self.lovedOrder(prefix: prefix)
        }
    }

    /// Floor on how many tracks an entity needs before it earns a tile. Categories are held
    /// to a higher bar because a 2-track "genre" is noise, not a discovery.
    func minTrackCount(for kind: DiscoverEntityKind) -> Int {
        switch kind {
        case .album, .artist, .playlist: return 2
        case .genre, .decade, .year: return 5
        }
    }

    func featuredAlbums(db: Database, signal: DiscoverSignal, hideDuplicates: Bool, limit: Int) throws -> [DiscoverEntityRow] {
        let duplicateClause = Self.duplicateClause(hideDuplicates, alias: "t")
        let artistFallbackClause = Self.duplicateClause(hideDuplicates, alias: "ta")
        // Grouping, HAVING and LIMIT all sit in a derived table over `tracks` alone, so
        // `albums` is joined to the surviving rows only. Selecting al.artwork_data in the
        // grouped query instead would drag every qualifying album's blob through the
        // ORDER BY sorter, and run the artist subqueries once per group rather than once
        // per returned row. The outer ORDER BY is required: a join over a LIMITed subquery
        // does not preserve its order.
        let sql = """
            SELECT
                al.id AS albumId,
                al.title AS title,
                al.artwork_data AS artwork_data,
                al.release_year AS release_year,
                g.trackCount AS trackCount,
                \(Self.albumPrimaryArtist(albumAlias: "al", duplicateClause: artistFallbackClause)) AS artistName
            FROM (
                SELECT
                    t.album_id AS albumId,
                    COUNT(t.id) AS trackCount,
                    \(Self.signalSelect)
                FROM tracks t
                WHERE t.album_id IS NOT NULL \(duplicateClause)
                GROUP BY t.album_id
                HAVING trackCount >= ? AND \(signal.sqlHaving)
                ORDER BY \(signalOrder(signal))
                LIMIT ?
            ) g
            JOIN albums al ON al.id = g.albumId
            ORDER BY \(signalOrder(signal, prefix: "g."))
        """

        return try Row.fetchAll(db, sql: sql, arguments: [minTrackCount(for: .album), limit]).map { row in
            let releaseYear: Int? = row["release_year"]
            return DiscoverEntityRow(
                ref: .album(id: row["albumId"], title: row["title"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: row["artwork_data"],
                year: releaseYear.map(String.init),
                artistName: row["artistName"]
            )
        }
    }

    func featuredArtists(
        db: Database,
        signal: DiscoverSignal,
        hideDuplicates: Bool,
        isImageFetchEnabled: Bool,
        limit: Int
    ) throws -> [DiscoverEntityRow] {
        let duplicateClause = Self.duplicateClause(hideDuplicates, alias: "t")
        // Same shape as featuredAlbums: group and limit first, so `artists` (and its
        // artwork blob) is only touched for the rows actually returned.
        let sql = """
            SELECT
                ar.id AS artistId,
                ar.name AS name,
                ar.artwork_data AS artwork_data,
                ar.image_source AS image_source,
                g.trackCount AS trackCount
            FROM (
                SELECT
                    ta.artist_id AS artistId,
                    COUNT(DISTINCT ta.track_id) AS trackCount,
                    \(Self.signalSelect)
                FROM track_artists ta
                JOIN tracks t ON t.id = ta.track_id \(duplicateClause)
                WHERE ta.role = 'artist'
                GROUP BY ta.artist_id
                HAVING trackCount >= ? AND \(signal.sqlHaving)
                ORDER BY \(signalOrder(signal))
                LIMIT ?
            ) g
            JOIN artists ar ON ar.id = g.artistId
            ORDER BY \(signalOrder(signal, prefix: "g."))
        """

        return try Row.fetchAll(db, sql: sql, arguments: [minTrackCount(for: .artist), limit]).map { row in
            DiscoverEntityRow(
                ref: .artist(id: row["artistId"], name: row["name"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: Self.artistArtwork(row: row, isImageFetchEnabled: isImageFetchEnabled),
                year: nil,
                artistName: nil
            )
        }
    }

    func featuredPlaylists(
        db: Database,
        signal: DiscoverSignal,
        hideDuplicates: Bool,
        limit: Int
    ) throws -> [DiscoverEntityRow] {
        let duplicateClause = Self.duplicateClause(hideDuplicates, alias: "t")
        // Only playlists with playlist_tracks rows can appear here, so auto-updating smart
        // playlists are structurally excluded; getDiscoverSmartPlaylistCandidates covers them.
        let sql = """
            SELECT
                p.id AS playlistId,
                p.name AS name,
                COUNT(pt.track_id) AS trackCount,
                \(Self.signalSelect)
            FROM playlists p
            JOIN playlist_tracks pt ON pt.playlist_id = p.id
            JOIN tracks t ON t.id = pt.track_id \(duplicateClause)
            GROUP BY p.id
            HAVING trackCount >= ? AND \(signal.sqlHaving)
            ORDER BY \(signalOrder(signal))
            LIMIT ?
        """

        return try Row.fetchAll(db, sql: sql, arguments: [minTrackCount(for: .playlist), limit]).compactMap { row in
            guard let idString: String = row["playlistId"], let playlistId = UUID(uuidString: idString) else { return nil }
            return DiscoverEntityRow(
                ref: .playlist(id: playlistId, name: row["name"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: nil,
                year: nil,
                artistName: nil,
                lastPlayed: row["lastPlayed"],
                hotPlays: row["hotPlays"] ?? 0,
                favoriteTracks: row["favoriteTracks"] ?? 0,
                totalPlays: row["totalPlays"] ?? 0
            )
        }
    }

    func featuredGenres(db: Database, signal: DiscoverSignal, hideDuplicates: Bool, limit: Int) throws -> [DiscoverEntityRow] {
        let duplicateClause = Self.duplicateClause(hideDuplicates, alias: "t")
        // Grouped on the denormalized column, matching getGenreFilterItems(): the
        // genres/track_genres tables split "Rock; Metal" into two rows that no other screen
        // would agree with. The Unknown bucket is excluded as noise.
        let sql = """
            SELECT
                t.genre AS name,
                COUNT(*) AS trackCount,
                \(Self.signalSelect)
            FROM tracks t
            WHERE \(CategorySQL.knownGenre(alias: "t")) \(duplicateClause)
            GROUP BY t.genre
            HAVING trackCount >= ? AND \(signal.sqlHaving)
            ORDER BY \(signalOrder(signal))
            LIMIT ?
        """

        return try Row.fetchAll(db, sql: sql, arguments: [minTrackCount(for: .genre), limit]).map { row in
            DiscoverEntityRow(
                ref: .category(kind: .genre, value: row["name"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: nil,
                year: nil,
                artistName: nil
            )
        }
    }

    func featuredDecades(db: Database, signal: DiscoverSignal, hideDuplicates: Bool, limit: Int) throws -> [DiscoverEntityRow] {
        let duplicateClause = Self.duplicateClause(hideDuplicates, alias: "t")
        // Same derivation as getDecadeFilterItems(), so the "1990s" value a tile carries
        // is one getTracksByFilterType can parse back.
        let sql = """
            SELECT
                \(CategorySQL.decadeExpression(alias: "t")) AS name,
                COUNT(*) AS trackCount,
                \(Self.signalSelect)
            FROM tracks t
            WHERE \(CategorySQL.knownYear(alias: "t")) \(duplicateClause)
            GROUP BY name
            HAVING trackCount >= ? AND \(signal.sqlHaving)
            ORDER BY \(signalOrder(signal))
            LIMIT ?
        """

        return try Row.fetchAll(db, sql: sql, arguments: [minTrackCount(for: .decade), limit]).map { row in
            DiscoverEntityRow(
                ref: .category(kind: .decade, value: row["name"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: nil,
                year: nil,
                artistName: nil
            )
        }
    }

    func featuredYears(db: Database, signal: DiscoverSignal, hideDuplicates: Bool, limit: Int) throws -> [DiscoverEntityRow] {
        let duplicateClause = Self.duplicateClause(hideDuplicates, alias: "t")
        let sql = """
            SELECT
                t.year AS name,
                COUNT(*) AS trackCount,
                \(Self.signalSelect)
            FROM tracks t
            WHERE \(CategorySQL.knownYear(alias: "t")) \(duplicateClause)
            GROUP BY t.year
            HAVING trackCount >= ? AND \(signal.sqlHaving)
            ORDER BY \(signalOrder(signal))
            LIMIT ?
        """

        return try Row.fetchAll(db, sql: sql, arguments: [minTrackCount(for: .year), limit]).map { row in
            DiscoverEntityRow(
                ref: .category(kind: .year, value: row["name"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: nil,
                year: nil,
                artistName: nil
            )
        }
    }
}

// MARK: - Recently Played Helpers

private extension DatabaseManager {
    func recentAlbums(db: Database, trackIds: [Int64], hideDuplicates: Bool, limit: Int) throws -> [DiscoverEntityRow] {
        let countClause = Self.duplicateClause(hideDuplicates, alias: "tc")
        let artistFallbackClause = Self.duplicateClause(hideDuplicates, alias: "ta")
        // Grouping + LIMIT sit in a subquery so the correlated count runs at most `limit`
        // times instead of once per album in the pool.
        let sql = """
            SELECT
                al.id AS albumId,
                al.title AS title,
                al.artwork_data AS artwork_data,
                al.release_year AS release_year,
                (SELECT COUNT(*) FROM tracks tc WHERE tc.album_id = al.id \(countClause)) AS trackCount,
                \(Self.albumPrimaryArtist(albumAlias: "al", duplicateClause: artistFallbackClause)) AS artistName
            FROM (
                SELECT t.album_id AS albumId,
                       MAX(t.last_played_date) AS lastPlayed,
                       COUNT(*) AS recentHits
                FROM tracks t
                WHERE t.id IN (\(self.databaseQuestionMarks(count: trackIds.count))) AND t.album_id IS NOT NULL
                GROUP BY t.album_id
                ORDER BY lastPlayed DESC, recentHits DESC
                LIMIT ?
            ) g
            JOIN albums al ON al.id = g.albumId
            ORDER BY g.lastPlayed DESC
        """

        return try Row.fetchAll(db, sql: sql, arguments: Self.arguments(trackIds, limit)).map { row in
            let releaseYear: Int? = row["release_year"]
            let artistName: String? = row["artistName"]
            return DiscoverEntityRow(
                ref: .album(id: row["albumId"], title: row["title"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: row["artwork_data"],
                year: releaseYear.map(String.init),
                artistName: (artistName?.isEmpty ?? true) ? nil : artistName
            )
        }
    }

    func recentArtists(
        db: Database,
        trackIds: [Int64],
        hideDuplicates: Bool,
        isImageFetchEnabled: Bool,
        limit: Int
    ) throws -> [DiscoverEntityRow] {
        let countClause = Self.duplicateClause(hideDuplicates, alias: "tc")
        let sql = """
            SELECT
                ar.id AS artistId,
                ar.name AS name,
                ar.artwork_data AS artwork_data,
                ar.image_source AS image_source,
                (SELECT COUNT(DISTINCT ta2.track_id)
                 FROM track_artists ta2
                 JOIN tracks tc ON tc.id = ta2.track_id \(countClause)
                 WHERE ta2.artist_id = ar.id AND ta2.role = 'artist') AS trackCount
            FROM (
                SELECT ta.artist_id AS artistId,
                       MAX(t.last_played_date) AS lastPlayed,
                       COUNT(*) AS recentHits
                FROM track_artists ta
                JOIN tracks t ON t.id = ta.track_id
                WHERE ta.role = 'artist' AND t.id IN (\(self.databaseQuestionMarks(count: trackIds.count)))
                GROUP BY ta.artist_id
                ORDER BY lastPlayed DESC, recentHits DESC
                LIMIT ?
            ) g
            JOIN artists ar ON ar.id = g.artistId
            ORDER BY g.lastPlayed DESC
        """

        return try Row.fetchAll(db, sql: sql, arguments: Self.arguments(trackIds, limit)).map { row in
            DiscoverEntityRow(
                ref: .artist(id: row["artistId"], name: row["name"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: Self.artistArtwork(row: row, isImageFetchEnabled: isImageFetchEnabled),
                year: nil,
                artistName: nil
            )
        }
    }

    func recentPlaylists(db: Database, trackIds: [Int64], hideDuplicates: Bool, limit: Int) throws -> [DiscoverEntityRow] {
        let countClause = Self.duplicateClause(hideDuplicates, alias: "tc")
        let sql = """
            SELECT
                p.id AS playlistId,
                p.name AS name,
                g.lastPlayed AS lastPlayed,
                (SELECT COUNT(*) FROM playlist_tracks pt2
                  JOIN tracks tc ON tc.id = pt2.track_id \(countClause)
                 WHERE pt2.playlist_id = p.id) AS trackCount
            FROM (
                SELECT pt.playlist_id AS pid,
                       MAX(t.last_played_date) AS lastPlayed,
                       COUNT(*) AS recentHits
                FROM playlist_tracks pt
                JOIN tracks t ON t.id = pt.track_id
                WHERE t.id IN (\(self.databaseQuestionMarks(count: trackIds.count)))
                GROUP BY pt.playlist_id
                ORDER BY lastPlayed DESC, recentHits DESC
                LIMIT ?
            ) g
            JOIN playlists p ON p.id = g.pid
            ORDER BY g.lastPlayed DESC
        """

        return try Row.fetchAll(db, sql: sql, arguments: Self.arguments(trackIds, limit)).compactMap { row in
            guard let idString: String = row["playlistId"], let playlistId = UUID(uuidString: idString) else { return nil }
            return DiscoverEntityRow(
                ref: .playlist(id: playlistId, name: row["name"] ?? ""),
                trackCount: row["trackCount"] ?? 0,
                artworkData: nil,
                year: nil,
                artistName: nil,
                lastPlayed: row["lastPlayed"]
            )
        }
    }

    func recentGenres(db: Database, trackIds: [Int64], counts: [String: Int], limit: Int) throws -> [DiscoverEntityRow] {
        let sql = """
            SELECT t.genre AS name,
                   MAX(t.last_played_date) AS lastPlayed,
                   COUNT(*) AS recentHits
            FROM tracks t
            WHERE t.id IN (\(self.databaseQuestionMarks(count: trackIds.count)))
              AND \(CategorySQL.knownGenre(alias: "t"))
            GROUP BY t.genre
            ORDER BY lastPlayed DESC, recentHits DESC
            LIMIT ?
        """

        return try Row.fetchAll(db, sql: sql, arguments: Self.arguments(trackIds, limit)).compactMap { row in
            let name: String = row["name"] ?? ""
            guard let count = counts[name], count > 0 else { return nil }
            return DiscoverEntityRow(
                ref: .category(kind: .genre, value: name),
                trackCount: count,
                artworkData: nil,
                year: nil,
                artistName: nil
            )
        }
    }

    func recentDecades(db: Database, trackIds: [Int64], counts: [String: Int], limit: Int) throws -> [DiscoverEntityRow] {
        let sql = """
            SELECT \(CategorySQL.decadeExpression(alias: "t")) AS name,
                   MAX(t.last_played_date) AS lastPlayed,
                   COUNT(*) AS recentHits
            FROM tracks t
            WHERE t.id IN (\(self.databaseQuestionMarks(count: trackIds.count)))
              AND \(CategorySQL.knownYear(alias: "t"))
            GROUP BY name
            ORDER BY lastPlayed DESC, recentHits DESC
            LIMIT ?
        """

        return try Row.fetchAll(db, sql: sql, arguments: Self.arguments(trackIds, limit)).compactMap { row in
            let name: String = row["name"] ?? ""
            guard let count = counts[name], count > 0 else { return nil }
            return DiscoverEntityRow(
                ref: .category(kind: .decade, value: name),
                trackCount: count,
                artworkData: nil,
                year: nil,
                artistName: nil
            )
        }
    }

    func recentYears(db: Database, trackIds: [Int64], counts: [String: Int], limit: Int) throws -> [DiscoverEntityRow] {
        let sql = """
            SELECT t.year AS name,
                   MAX(t.last_played_date) AS lastPlayed,
                   COUNT(*) AS recentHits
            FROM tracks t
            WHERE t.id IN (\(self.databaseQuestionMarks(count: trackIds.count)))
              AND \(CategorySQL.knownYear(alias: "t"))
            GROUP BY t.year
            ORDER BY lastPlayed DESC, recentHits DESC
            LIMIT ?
        """

        return try Row.fetchAll(db, sql: sql, arguments: Self.arguments(trackIds, limit)).compactMap { row in
            let name: String = row["name"] ?? ""
            guard let count = counts[name], count > 0 else { return nil }
            return DiscoverEntityRow(
                ref: .category(kind: .year, value: name),
                trackCount: count,
                artworkData: nil,
                year: nil,
                artistName: nil
            )
        }
    }
}

// MARK: - Shared Helpers

extension DatabaseManager {
    /// Library-wide genre counts in one grouped pass. Predicate matches the known-genre
    /// branch of getGenreFilterItems() so tile counts agree with the Library sidebar.
    func discoverGenreTrackCounts(db: Database, hideDuplicates: Bool) throws -> [String: Int] {
        let duplicateClause = Self.duplicateClause(hideDuplicates)
        let sql = """
            SELECT genre AS name, COUNT(*) AS track_count
            FROM tracks
            WHERE \(CategorySQL.knownGenre()) \(duplicateClause)
            GROUP BY genre
        """
        return try Self.countMap(Row.fetchAll(db, sql: sql))
    }

    /// Library-wide exact-year counts in one grouped pass.
    func discoverYearTrackCounts(db: Database, hideDuplicates: Bool) throws -> [String: Int] {
        let duplicateClause = Self.duplicateClause(hideDuplicates)
        let sql = """
            SELECT year AS name, COUNT(*) AS track_count
            FROM tracks
            WHERE \(CategorySQL.knownYear()) \(duplicateClause)
            GROUP BY year
        """
        return try Self.countMap(Row.fetchAll(db, sql: sql))
    }

    /// Decade totals derive from the exact-year pass so Recently Played and sticky
    /// resolution do not group the same track column twice.
    static func discoverDecadeTrackCounts(from yearCounts: [String: Int]) -> [String: Int] {
        yearCounts.reduce(into: [:]) { counts, entry in
            counts["\(entry.key.prefix(3))0s", default: 0] += entry.value
        }
    }

    static func countMap(_ rows: [Row]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for row in rows {
            guard let name: String = row["name"] else { continue }
            counts[name] = row["track_count"] ?? 0
        }
        return counts
    }

    /// `applyDuplicateFilter` covers the GRDB query-interface path only, so raw SQL needs
    /// its own alias-aware form.
    static func duplicateClause(_ hideDuplicates: Bool, alias: String? = nil) -> String {
        guard hideDuplicates else { return "" }
        let prefix = alias.map { "\($0)." } ?? ""
        return "AND \(prefix)is_duplicate = 0"
    }

    /// Album primary artist: the `album_artists` junction, then the album-artist tag, then
    /// any track artist. Shared by all three album queries, which previously disagreed and
    /// gave one album a subtitle in Featured but not in Recently Played.
    ///
    /// Correlated subqueries rather than `MAX(t.album_artist)` so one expression serves the
    /// grouped and ungrouped queries alike.
    static func albumPrimaryArtist(albumAlias: String, duplicateClause: String) -> String {
        """
        COALESCE(
            (SELECT ar.name
             FROM album_artists aa
             JOIN artists ar ON ar.id = aa.artist_id
             WHERE aa.album_id = \(albumAlias).id AND aa.role = 'primary'
             ORDER BY aa.position
             LIMIT 1),
            (SELECT NULLIF(ta.album_artist, '')
             FROM tracks ta
             WHERE ta.album_id = \(albumAlias).id AND NULLIF(ta.album_artist, '') IS NOT NULL \(duplicateClause)
             LIMIT 1),
            (SELECT ta.artist FROM tracks ta WHERE ta.album_id = \(albumAlias).id \(duplicateClause) LIMIT 1)
        )
        """
    }

    static func arguments(_ trackIds: [Int64], _ limit: Int) -> StatementArguments {
        var values: [any DatabaseValueConvertible] = trackIds
        values.append(limit)
        return StatementArguments(values)
    }

    static func arguments(_ values: [any DatabaseValueConvertible]) -> StatementArguments {
        StatementArguments(values)
    }

    /// Mirrors getArtistEntities(): when online artist images are enabled, only surface
    /// `artwork_data` if `image_source` proves it was fetched rather than carried over
    /// from album art.
    static func artistArtwork(row: Row, isImageFetchEnabled: Bool) -> Data? {
        let artworkData: Data? = row["artwork_data"]
        let imageSource: String? = row["image_source"]
        return isImageFetchEnabled ? (imageSource != nil ? artworkData : nil) : artworkData
    }
}
