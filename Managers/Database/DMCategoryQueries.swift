//
// DatabaseManager class extension
//
// This extension contains all the methods for querying category items for
// Album, Artist, Album artist, Composer, Genre, Decades, and Years.
//

import Foundation
import GRDB

extension DatabaseManager {
    // MARK: - Helper Methods
    
    private func rowToFilterItem(_ row: Row, filterType: LibraryFilterType) -> LibraryFilterItem {
        let name = row["name"] as? String ?? ""
        let columnName = (filterType == .decades) ? "decade" : "name"
        let actualName = row[columnName] as? String ?? name
        
        let count: Int
        if let count64 = row["track_count"] as? Int64 {
            count = Int(count64)
        } else if let countInt = row["track_count"] as? Int {
            count = countInt
        } else {
            count = 0
        }
        
        // Albums carry their id so a merge can target the exact album (titles aren't unique).
        let albumId: Int64? = filterType == .albums ? row["id"] : nil

        return LibraryFilterItem(
            name: actualName,
            count: count,
            filterType: filterType,
            albumId: albumId
        )
    }
    
    // MARK: - Home - Entities
    
    /// Get all artist entities
    func getArtistEntities() -> [ArtistEntity] {
        let isImageFetchEnabled = ArtistBioManager.shared.isArtistInfoFetchEnabled

        do {
            return try dbQueue.read { db in
                // Live count honoring the hide-duplicates setting, so the grid matches the detail view.
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND tracks.is_duplicate = 0" : ""
                let sql = """
                    SELECT
                        artists.name,
                        artists.artwork_data,
                        artists.image_source,
                        COUNT(DISTINCT track_artists.track_id) as trackCount
                    FROM artists
                    JOIN track_artists ON track_artists.artist_id = artists.id AND track_artists.role = 'artist'
                    JOIN tracks ON tracks.id = track_artists.track_id \(duplicateClause)
                    GROUP BY artists.id
                    HAVING trackCount > 0
                    ORDER BY artists.sort_name
                """

                struct ArtistInfo: FetchableRecord {
                    let name: String
                    let artworkData: Data?
                    let imageSource: String?
                    let trackCount: Int

                    init(row: Row) throws {
                        name = row["name"]
                        artworkData = row["artwork_data"]
                        imageSource = row["image_source"]
                        trackCount = row["trackCount"] ?? 0
                    }
                }

                return try ArtistInfo.fetchAll(db, sql: sql).map { info in
                    // When fetch enabled: show fetched image or placeholder; when disabled: show album art
                    let artworkData = isImageFetchEnabled
                        ? (info.imageSource != nil ? info.artworkData : nil)
                        : info.artworkData

                    return ArtistEntity(
                        name: info.name,
                        trackCount: info.trackCount,
                        artworkData: artworkData
                    )
                }
            }
        } catch {
            Logger.error("Failed to get artist entities: \(error)")
            return []
        }
    }

    /// Get all album entities without N+1 queries
    func getAlbumEntities() -> [AlbumEntity] {
        do {
            return try dbQueue.read { db in
                // Prefer the album's primary artist from the album_artists junction
                // (which findOrCreateAlbum populates, including "Various Artists" for compilations)
                // before falling back to per-track tag aggregates.
                // Count live joined tracks (not albums.total_tracks, which drifts with duplicates),
                // honoring the hide-duplicates setting so the grid matches the detail view.
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND tracks.is_duplicate = 0" : ""
                let sql = """
                    SELECT
                        albums.id,
                        albums.title,
                        COUNT(tracks.id) as trackCount,
                        albums.artwork_data,
                        albums.release_year,
                        COALESCE(SUM(tracks.duration), 0) as totalDuration,
                        COALESCE(
                            (SELECT artists.name
                             FROM album_artists
                             JOIN artists ON artists.id = album_artists.artist_id
                             WHERE album_artists.album_id = albums.id
                               AND album_artists.role = 'primary'
                             ORDER BY album_artists.position
                             LIMIT 1),
                            NULLIF(MAX(tracks.album_artist), ''),
                            MAX(tracks.artist)
                        ) as artistName,
                        albums.created_at
                    FROM albums
                    LEFT JOIN tracks ON albums.id = tracks.album_id \(duplicateClause)
                    GROUP BY albums.id
                    HAVING trackCount > 0
                    ORDER BY albums.sort_title
                """
                
                struct AlbumInfo: FetchableRecord {
                    let id: Int64?
                    let title: String
                    let totalTracks: Int
                    let artworkData: Data?
                    let releaseYear: Int?
                    let totalDuration: Double
                    let artistName: String?
                    let createdAt: Date?
                    
                    init(row: Row) throws {
                        id = row["id"]
                        title = row["title"]
                        totalTracks = row["trackCount"] ?? 0
                        artworkData = row["artwork_data"]
                        releaseYear = row["release_year"]
                        totalDuration = row["totalDuration"] ?? 0
                        artistName = row["artistName"]
                        createdAt = row["created_at"]
                    }
                }
                
                let albumInfos = try AlbumInfo.fetchAll(db, sql: sql)
                
                return albumInfos.map { info in
                    AlbumEntity(
                        name: info.title,
                        trackCount: info.totalTracks,
                        artworkData: info.artworkData,
                        albumId: info.id,
                        year: info.releaseYear.map { String($0) } ?? "",
                        duration: info.totalDuration,
                        artistName: info.artistName,
                        dateAdded: info.createdAt
                    )
                }
            }
        } catch {
            Logger.error("Failed to get album entities: \(error)")
            return []
        }
    }

    // MARK: - Library - Filter Items
    
    /// Get artist filter items with counts
    func getArtistFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND t.is_duplicate = 0" : ""
                
                let sql = """
                    SELECT
                        a.name,
                        a.sort_name,
                        COUNT(DISTINCT ta.track_id) as track_count
                    FROM artists a
                    INNER JOIN track_artists ta ON a.id = ta.artist_id
                    INNER JOIN tracks t ON ta.track_id = t.id
                    WHERE ta.role = 'artist' \(duplicateClause)
                    GROUP BY a.id, a.name, a.sort_name
                    HAVING track_count > 0
                    
                    UNION ALL
                    
                    SELECT
                        'Unknown Artist' as name,
                        'Unknown Artist' as sort_name,
                        COUNT(*) as track_count
                    FROM tracks t
                    WHERE t.artist = 'Unknown Artist' \(duplicateClause)
                    HAVING COUNT(*) > 0
                    
                    ORDER BY sort_name COLLATE NOCASE
                    """
                
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in rowToFilterItem(row, filterType: .artists) }
            }
        } catch {
            Logger.error("Failed to get artist filter items: \(error)")
            return []
        }
    }
    
    /// Get album filter items with counts
    func getAlbumFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                
                let albumsQuery = if hideDuplicates {
                    """
                    SELECT
                        a.title as name,
                        a.sort_title,
                        COUNT(DISTINCT CASE WHEN t.is_duplicate = 0 THEN t.id END) as track_count,
                        a.id as id
                    FROM albums a
                    LEFT JOIN tracks t ON a.id = t.album_id
                    GROUP BY a.id, a.title, a.sort_title
                    HAVING track_count > 0
                    """
                } else {
                    """
                    SELECT
                        title as name,
                        sort_title,
                        total_tracks as track_count,
                        id
                    FROM albums
                    WHERE total_tracks > 0
                    """
                }

                let duplicateClause = hideDuplicates ? "AND t.is_duplicate = 0" : ""
                let unknownAlbumQuery = """
                    SELECT
                        'Unknown Album' as name,
                        'Unknown Album' as sort_title,
                        COUNT(*) as track_count,
                        NULL as id
                    FROM tracks t
                    WHERE t.album = 'Unknown Album' \(duplicateClause)
                    GROUP BY t.album
                """
                
                let sql = """
                    \(albumsQuery)
                    
                    UNION ALL
                    
                    \(unknownAlbumQuery)
                    
                    ORDER BY sort_title COLLATE NOCASE
                """
                
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in rowToFilterItem(row, filterType: .albums) }
            }
        } catch {
            Logger.error("Failed to get album filter items: \(error)")
            return []
        }
    }

    /// Get album artist filter items with counts
    func getAlbumArtistFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND t.is_duplicate = 0" : ""
                
                let sql = """
                    SELECT
                        a.name,
                        a.sort_name,
                        COUNT(DISTINCT ta.track_id) as track_count
                    FROM artists a
                    INNER JOIN track_artists ta ON a.id = ta.artist_id
                    INNER JOIN tracks t ON ta.track_id = t.id
                    WHERE ta.role = 'album_artist' \(duplicateClause)
                    GROUP BY a.id, a.name, a.sort_name
                    HAVING track_count > 0
                    
                    UNION ALL
                    
                    SELECT
                        'Unknown Album Artist' as name,
                        'Unknown Album Artist' as sort_name,
                        COUNT(*) as track_count
                    FROM tracks t
                    WHERE t.album_artist = 'Unknown Album Artist' \(duplicateClause)
                    HAVING COUNT(*) > 0
                    
                    ORDER BY sort_name COLLATE NOCASE
                    """
                
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in rowToFilterItem(row, filterType: .albumArtists) }
            }
        } catch {
            Logger.error("Failed to get album artist filter items: \(error)")
            return []
        }
    }

    /// Get composer filter items with counts
    func getComposerFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND t.is_duplicate = 0" : ""
                
                let sql = """
                    SELECT
                        a.name,
                        a.sort_name,
                        COUNT(DISTINCT ta.track_id) as track_count
                    FROM artists a
                    INNER JOIN track_artists ta ON a.id = ta.artist_id
                    INNER JOIN tracks t ON ta.track_id = t.id
                    WHERE ta.role = 'composer' \(duplicateClause)
                    GROUP BY a.id, a.name, a.sort_name
                    HAVING track_count > 0
                    
                    UNION ALL
                    
                    SELECT
                        'Unknown Composer' as name,
                        'Unknown Composer' as sort_name,
                        COUNT(*) as track_count
                    FROM tracks t
                    WHERE t.composer = 'Unknown Composer' \(duplicateClause)
                    HAVING COUNT(*) > 0
                    
                    ORDER BY sort_name COLLATE NOCASE
                    """
                
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in rowToFilterItem(row, filterType: .composers) }
            }
        } catch {
            Logger.error("Failed to get composer filter items: \(error)")
            return []
        }
    }

    /// Get genre filter items with counts
    func getGenreFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND is_duplicate = 0" : ""
                
                let sql = """
                    SELECT
                        genre as name,
                        COUNT(*) as track_count
                    FROM tracks
                    WHERE genre IS NOT NULL AND genre != '' AND genre != 'Unknown Genre' \(duplicateClause)
                    GROUP BY genre
                    
                    UNION ALL
                    
                    SELECT
                        'Unknown Genre' as name,
                        COUNT(*) as track_count
                    FROM tracks
                    WHERE (genre IS NULL OR genre = '' OR genre = 'Unknown Genre') \(duplicateClause)
                    HAVING COUNT(*) > 0
                    
                    ORDER BY name COLLATE NOCASE
                """
                
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in rowToFilterItem(row, filterType: .genres) }
            }
        } catch {
            Logger.error("Failed to get genre filter items: \(error)")
            return []
        }
    }

    /// Get decade filter items with counts
    func getDecadeFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND is_duplicate = 0" : ""
                
                let sql = """
                    SELECT
                        CASE
                            WHEN year IS NULL OR year = '' OR year = 'Unknown Year' THEN 'Unknown Decade'
                            ELSE SUBSTR(year, 1, 3) || '0s'
                        END as decade,
                        COUNT(*) as track_count
                    FROM tracks
                    WHERE 1=1 \(duplicateClause)
                    GROUP BY decade
                    HAVING track_count > 0
                    ORDER BY
                        CASE WHEN decade = 'Unknown Decade' THEN '9999' ELSE decade END DESC
                """
                
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in rowToFilterItem(row, filterType: .decades) }
            }
        } catch {
            Logger.error("Failed to get decade filter items: \(error)")
            return []
        }
    }

    /// Get year filter items with counts
    func getYearFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
                let duplicateClause = hideDuplicates ? "AND is_duplicate = 0" : ""
                
                let sql = """
                    SELECT
                        year as name,
                        COUNT(*) as track_count
                    FROM tracks
                    WHERE year IS NOT NULL AND year != '' AND year != 'Unknown Year' \(duplicateClause)
                    GROUP BY year
                    
                    UNION ALL
                    
                    SELECT
                        'Unknown Year' as name,
                        COUNT(*) as track_count
                    FROM tracks
                    WHERE (year IS NULL OR year = '' OR year = 'Unknown Year') \(duplicateClause)
                    HAVING COUNT(*) > 0
                    
                    ORDER BY name DESC
                """
                
                let rows = try Row.fetchAll(db, sql: sql)
                return rows.map { row in rowToFilterItem(row, filterType: .years) }
            }
        } catch {
            Logger.error("Failed to get year filter items: \(error)")
            return []
        }
    }
}
