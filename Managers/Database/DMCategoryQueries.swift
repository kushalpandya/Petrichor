//
// DatabaseManager class extension
//
// This extension contains all the methods for querying category items for
// Album, Artist, Album artist, Composer, Genre, Decades, and Years.
//

import Foundation
import GRDB

extension DatabaseManager {
    // MARK: - Entities
    
    /// Get all artist entities - already efficient, using pure GRDB
    func getArtistEntities() -> [ArtistEntity] {
        do {
            return try dbQueue.read { db in
                let artists = try Artist
                    .filter(Artist.Columns.totalTracks > 0)
                    .order(Artist.Columns.sortName)
                    .fetchAll(db)
                
                return artists.map { artist in
                    ArtistEntity(
                        name: artist.name,
                        trackCount: artist.totalTracks,
                        artworkData: artist.artworkData
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
                let sql = """
                    SELECT
                        albums.id,
                        albums.title,
                        albums.total_tracks,
                        albums.artwork_data,
                        albums.release_year,
                        COALESCE(SUM(tracks.duration), 0) as totalDuration,
                        primaryArtist.name as artistName
                    FROM albums
                    LEFT JOIN tracks ON albums.id = tracks.album_id AND tracks.is_duplicate = 0
                    LEFT JOIN (
                        SELECT aa.album_id, a.name
                        FROM album_artists aa
                        INNER JOIN artists a ON aa.artist_id = a.id
                        WHERE aa.role = 'primary' AND aa.position = 0
                    ) primaryArtist ON albums.id = primaryArtist.album_id
                    WHERE albums.total_tracks > 0
                    GROUP BY albums.id
                    ORDER BY albums.sort_title
                """
                
                // Define a record to capture the results
                struct AlbumInfo: FetchableRecord {
                    let id: Int64?
                    let title: String
                    let totalTracks: Int
                    let artworkData: Data?
                    let releaseYear: Int?
                    let totalDuration: Double
                    let artistName: String?
                    
                    init(row: Row) throws {
                        id = row["id"]
                        title = row["title"]
                        totalTracks = row["total_tracks"] ?? 0
                        artworkData = row["artwork_data"]
                        releaseYear = row["release_year"]
                        totalDuration = row["totalDuration"] ?? 0.0
                        artistName = row["artistName"]
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
                        artistName: info.artistName
                    )
                }
            }
        } catch {
            Logger.error("Failed to get album entities: \(error)")
            return []
        }
    }
    
    // MARK: - Library Categories
    
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
                    
                    ORDER BY sort_name
                """
                
                let rows = try Row.fetchAll(db, sql: sql)
                
                return rows.map { row in
                    let name = row["name"] as? String ?? ""
                    let countValue: Int
                    if let count64 = row["track_count"] as? Int64 {
                        countValue = Int(count64)
                    } else if let countInt = row["track_count"] as? Int {
                        countValue = countInt
                    } else {
                        countValue = 0
                    }
                    return LibraryFilterItem(
                        name: name,
                        count: countValue,
                        filterType: .artists
                    )
                }
            }
        } catch {
            Logger.error("Failed to get artist filter items: \(error)")
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
                    
                    ORDER BY sort_name
                """
                
                let rows = try Row.fetchAll(db, sql: sql)
                
                return rows.map { row in
                    let name = row["name"] as? String ?? ""
                    let countValue: Int
                    if let count64 = row["track_count"] as? Int64 {
                        countValue = Int(count64)
                    } else if let countInt = row["track_count"] as? Int {
                        countValue = countInt
                    } else {
                        countValue = 0
                    }
                    return LibraryFilterItem(
                        name: name,
                        count: countValue,
                        filterType: .albumArtists
                    )
                }
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
                    
                    ORDER BY sort_name
                """
                
                let rows = try Row.fetchAll(db, sql: sql)
                
                return rows.map { row in
                    let name = row["name"] as? String ?? ""
                    let countValue: Int
                    if let count64 = row["track_count"] as? Int64 {
                        countValue = Int(count64)
                    } else if let countInt = row["track_count"] as? Int {
                        countValue = countInt
                    } else {
                        countValue = 0
                    }
                    return LibraryFilterItem(
                        name: name,
                        count: countValue,
                        filterType: .composers
                    )
                }
            }
        } catch {
            Logger.error("Failed to get composer filter items: \(error)")
            return []
        }
    }

    /// Get album filter items with counts
    func getAlbumFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")

                let sql: String
                if hideDuplicates {
                    sql = """
                        SELECT
                            a.title as name,
                            a.sort_title,
                            COUNT(CASE WHEN t.is_duplicate = 0 THEN t.id END) as track_count
                        FROM albums a
                        LEFT JOIN tracks t ON a.id = t.album_id
                        GROUP BY a.id, a.title, a.sort_title
                        HAVING track_count > 0
                        
                        UNION ALL
                        
                        SELECT
                            'Unknown Album' as name,
                            'Unknown Album' as sort_title,
                            COUNT(*) as track_count
                        FROM tracks t
                        WHERE t.album = 'Unknown Album' AND t.is_duplicate = 0
                        HAVING COUNT(*) > 0
                        
                        ORDER BY sort_title
                    """
                } else {
                    sql = """
                        SELECT
                            a.title as name,
                            a.sort_title,
                            COUNT(t.id) as track_count
                        FROM albums a
                        LEFT JOIN tracks t ON a.id = t.album_id
                        GROUP BY a.id, a.title, a.sort_title
                        HAVING track_count > 0
                        
                        UNION ALL
                        
                        SELECT
                            'Unknown Album' as name,
                            'Unknown Album' as sort_title,
                            COUNT(*) as track_count
                        FROM tracks t
                        WHERE t.album = 'Unknown Album'
                        HAVING COUNT(*) > 0
                        
                        ORDER BY sort_title
                    """
                }
                
                let rows = try Row.fetchAll(db, sql: sql)
                
                return rows.map { row in
                    let name = row["name"] as? String ?? ""
                    let countValue: Int
                    if let count64 = row["track_count"] as? Int64 {
                        countValue = Int(count64)
                    } else if let countInt = row["track_count"] as? Int {
                        countValue = countInt
                    } else {
                        countValue = 0
                    }
                    return LibraryFilterItem(
                        name: name,
                        count: countValue,
                        filterType: .albums
                    )
                }
            }
        } catch {
            Logger.error("Failed to get album filter items: \(error)")
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
                
                return rows.map { row in
                    let name = row["name"] as? String ?? ""
                    let countValue: Int
                    if let count64 = row["track_count"] as? Int64 {
                        countValue = Int(count64)
                    } else if let countInt = row["track_count"] as? Int {
                        countValue = countInt
                    } else {
                        countValue = 0
                    }
                    return LibraryFilterItem(
                        name: name,
                        count: countValue,
                        filterType: .genres
                    )
                }
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
                
                return rows.map { row in
                    let name = row["decade"] as? String ?? ""
                    let countValue: Int
                    if let count64 = row["track_count"] as? Int64 {
                        countValue = Int(count64)
                    } else if let countInt = row["track_count"] as? Int {
                        countValue = countInt
                    } else {
                        countValue = 0
                    }
                    return LibraryFilterItem(
                        name: name,
                        count: countValue,
                        filterType: .decades
                    )
                }
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
                
                return rows.map { row in
                    let name = row["name"] as? String ?? ""
                    let countValue: Int
                    if let count64 = row["track_count"] as? Int64 {
                        countValue = Int(count64)
                    } else if let countInt = row["track_count"] as? Int {
                        countValue = countInt
                    } else {
                        countValue = 0
                    }
                    return LibraryFilterItem(
                        name: name,
                        count: countValue,
                        filterType: .years
                    )
                }
            }
        } catch {
            Logger.error("Failed to get year filter items: \(error)")
            return []
        }
    }
}
