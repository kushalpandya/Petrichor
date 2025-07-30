//
// DatabaseManager class extension
//
// This extension contains all the methods for querying records from the database based on
// various criteria.
//

import Foundation
import GRDB

extension DatabaseManager {
    /// Populate track album art from albums table
    func populateAlbumArtworkForTracks(_ tracks: inout [Track], db: Database) throws {
        // Get unique album IDs
        let albumIds = tracks.compactMap { $0.albumId }.removingDuplicates()
        
        guard !albumIds.isEmpty else { return }
        
        // Fetch only id and artwork_data columns
        let request = Album
            .select(Album.Columns.id, Album.Columns.artworkData)
            .filter(albumIds.contains(Album.Columns.id))
        
        let rows = try Row.fetchAll(db, request)
        
        // Build artwork map
        let albumArtworkMap: [Int64: Data] = rows.reduce(into: [:]) { dict, row in
            if let id: Int64 = row["id"],
               let artwork: Data = row["artwork_data"] {
                dict[id] = artwork
            }
        }
        
        // Populate the transient property
        for i in 0..<tracks.count {
            if let albumId = tracks[i].albumId,
               let albumArtwork = albumArtworkMap[albumId] {
                tracks[i].albumArtworkData = albumArtwork
            }
        }
    }

    func populateAlbumArtworkForTracks(_ tracks: inout [Track]) {
        do {
            try dbQueue.read { db in
                try populateAlbumArtworkForTracks(&tracks, db: db)
            }
        } catch {
            Logger.error("Failed to populate album artwork: \(error)")
        }
    }
    
    /// Populate album artwork for a single FullTrack
    func populateAlbumArtworkForFullTrack(_ track: inout FullTrack) {
        guard let albumId = track.albumId else { return }
        
        do {
            if let artworkData = try dbQueue.read({ db in
                try Album
                    .select(Album.Columns.artworkData)
                    .filter(Album.Columns.id == albumId)
                    .fetchOne(db)?[Album.Columns.artworkData] as Data?
            }) {
                track.albumArtworkData = artworkData
            }
        } catch {
            Logger.error("Failed to populate album artwork for full track: \(error)")
        }
    }
    
    /// Get tracks for the Discover feature
    func getDiscoverTracks(limit: Int = 50, excludeTrackIds: Set<Int64> = []) -> [Track] {
        do {
            return try dbQueue.read { db in
                // First try to get unplayed tracks
                var query = applyDuplicateFilter(Track.all())
                    .filter(Track.Columns.playCount == 0)
                
                if !excludeTrackIds.isEmpty {
                    query = query.filter(!excludeTrackIds.contains(Track.Columns.trackId))
                }
                
                // Order randomly
                query = query.order(sql: "RANDOM()")
                    .limit(limit)
                
                var tracks = try query.fetchAll(db)
                
                // If we don't have enough unplayed tracks, fill with least recently played
                if tracks.count < limit {
                    let remaining = limit - tracks.count
                    let existingIds = Set(tracks.compactMap { $0.trackId })
                        .union(excludeTrackIds)
                    
                    let additionalTracks = try applyDuplicateFilter(Track.all())
                        .filter(!existingIds.contains(Track.Columns.trackId))
                        .order(
                            Track.Columns.lastPlayedDate.asc,
                            Track.Columns.playCount.asc
                        )
                        .limit(remaining)
                        .fetchAll(db)
                    
                    tracks.append(contentsOf: additionalTracks)
                }
                
                try populateAlbumArtworkForTracks(&tracks, db: db)
                
                return tracks
            }
        } catch {
            Logger.error("Failed to get discover tracks: \(error)")
            return []
        }
    }

    /// Get tracks by IDs (for loading saved discover tracks)
    func getTracks(byIds trackIds: [Int64]) -> [Track] {
        do {
            return try dbQueue.read { db in
                try Track
                    .filter(trackIds.contains(Track.Columns.trackId))
                    .fetchAll(db)
            }
        } catch {
            Logger.error("Failed to get tracks by IDs: \(error)")
            return []
        }
    }
    
    /// Get total track count without loading tracks
    func getTotalTrackCount() -> Int {
        do {
            return try dbQueue.read { db in
                try applyDuplicateFilter(Track.all()).fetchCount(db)
            }
        } catch {
            Logger.error("Failed to get total track count: \(error)")
            return 0
        }
    }
    
    /// Get total duration of all tracks in the library
    func getTotalDuration() -> Double {
        do {
            return try dbQueue.read { db in
                let result = try applyDuplicateFilter(Track.all())
                    .select(sum(Track.Columns.duration), as: Double.self)
                    .fetchOne(db)
                
                return result ?? 0.0
            }
        } catch {
            Logger.error("Failed to get total duration: \(error)")
            return 0.0
        }
    }

    /// Get distinct values for a filter type using normalized tables
    func getDistinctValues(for filterType: LibraryFilterType) -> [String] {
        do {
            return try dbQueue.read { db in
                switch filterType {
                case .artists, .albumArtists, .composers:
                    // Get from normalized artists table
                    let artists = try Artist
                        .select(Artist.Columns.name, as: String.self)
                        .order(Artist.Columns.sortName)
                        .fetchAll(db)

                    // Add "Unknown" placeholder if there are tracks without artists
                    var results = artists
                    if try applyDuplicateFilter(Track.all()).filter(Track.Columns.artist == filterType.unknownPlaceholder).fetchCount(db) > 0 {
                        results.append(filterType.unknownPlaceholder)
                    }
                    return results

                case .albums:
                    // Get from normalized albums table
                    let albums = try Album
                        .select(Album.Columns.title, as: String.self)
                        .order(Album.Columns.sortTitle)
                        .fetchAll(db)

                    // Add "Unknown Album" if needed
                    var results = albums
                    if try applyDuplicateFilter(Track.all()).filter(Track.Columns.album == "Unknown Album").fetchCount(db) > 0 {
                        results.append("Unknown Album")
                    }
                    return results

                case .genres:
                    // Get from normalized genres table
                    let genres = try Genre
                        .select(Genre.Columns.name, as: String.self)
                        .order(Genre.Columns.name)
                        .fetchAll(db)

                    // Add "Unknown Genre" if needed
                    var results = genres
                    if try applyDuplicateFilter(Track.all()).filter(Track.Columns.genre == "Unknown Genre").fetchCount(db) > 0 {
                        results.append("Unknown Genre")
                    }
                    return results
                    
                case .decades:
                    // Get all years and convert to decades
                    let years = try applyDuplicateFilter(Track.all())
                        .select(Track.Columns.year, as: String.self)
                        .filter(Track.Columns.year != "")
                        .filter(Track.Columns.year != "Unknown Year")
                        .distinct()
                        .fetchAll(db)
                    
                    // Convert years to decades
                    var decadesSet = Set<String>()
                    for year in years {
                        if let yearInt = Int(year.prefix(4)) {
                            let decade = (yearInt / 10) * 10
                            decadesSet.insert("\(decade)s")
                        }
                    }
                    
                    // Sort decades in descending order
                    return decadesSet.sorted { decade1, decade2 in
                        let d1 = Int(decade1.dropLast()) ?? 0
                        let d2 = Int(decade2.dropLast()) ?? 0
                        return d1 > d2
                    }

                case .years:
                    // Years don't have a normalized table, use tracks directly
                    return try applyDuplicateFilter(Track.all())
                        .select(Track.Columns.year, as: String.self)
                        .filter(Track.Columns.year != "")
                        .distinct()
                        .order(Track.Columns.year.desc)
                        .fetchAll(db)
                }
            }
        } catch {
            Logger.error("Failed to get distinct values for \(filterType): \(error)")
            return []
        }
    }

    /// Get tracks by filter type and value using normalized tables
    func getTracksByFilterType(_ filterType: LibraryFilterType, value: String) -> [Track] {
        do {
            return try dbQueue.read { db in
                var tracks: [Track] = []
                
                switch filterType {
                case .artists, .albumArtists, .composers:
                    // For artist-based filters, use normalized matching
                    let normalizedSearchName = ArtistParser.normalizeArtistName(value)
                    
                    guard let artist = try Artist
                        .filter((Artist.Columns.name == value) || (Artist.Columns.normalizedName == normalizedSearchName))
                        .fetchOne(db),
                        let artistId = artist.id else {
                        return []
                    }
                    
                    // Get track IDs for this artist
                    let trackIds = try TrackArtist
                        .filter(TrackArtist.Columns.artistId == artistId)
                        .select(TrackArtist.Columns.trackId, as: Int64.self)
                        .fetchAll(db)
                    
                    tracks = try Track.lightweightRequest()
                        .filter(trackIds.contains(Track.Columns.trackId))
                        .fetchAll(db)
                        
                case .albums:
                    tracks = try Track.lightweightRequest()
                        .filter(Track.Columns.album == value)
                        .fetchAll(db)
                        
                case .genres:
                    tracks = try Track.lightweightRequest()
                        .filter(Track.Columns.genre == value)
                        .fetchAll(db)
                        
                case .years:
                    tracks = try Track.lightweightRequest()
                        .filter(Track.Columns.year == value)
                        .fetchAll(db)
                        
                case .decades:
                    let decade = value.replacingOccurrences(of: "s", with: "")
                    if let decadeInt = Int(decade) {
                        let startYear = String(decadeInt)
                        let endYear = String(decadeInt + 9)
                        tracks = try Track.lightweightRequest()
                            .filter(Track.Columns.year >= startYear && Track.Columns.year <= endYear)
                            .fetchAll(db)
                    }
                }
                
                // Order results
                tracks = tracks.sorted { $0.title < $1.title }
                
                // Populate album artwork
                try populateAlbumArtworkForTracks(&tracks, db: db)
                
                return tracks
            }
        } catch {
            Logger.error("Failed to get tracks by filter type: \(error)")
            return []
        }
    }

    /// Get tracks where the filter value is contained (for multi-artist parsing)
    func getTracksByFilterTypeContaining(_ filterType: LibraryFilterType, value: String) -> [Track] {
        do {
            return try dbQueue.read { db in
                // This is specifically for multi-artist fields
                guard filterType.usesMultiArtistParsing else {
                    return getTracksByFilterType(filterType, value: value)
                }

                // Find the artist (handles normalized name matching)
                let normalizedSearchName = ArtistParser.normalizeArtistName(value)

                guard let artist = try Artist
                    .filter((Artist.Columns.name == value) || (Artist.Columns.normalizedName == normalizedSearchName))
                    .fetchOne(db),
                    let artistId = artist.id else {
                    return []
                }

                // Get all tracks for this artist (any role)
                let trackIds = try TrackArtist
                    .filter(TrackArtist.Columns.artistId == artistId)
                    .select(TrackArtist.Columns.trackId, as: Int64.self)
                    .fetchAll(db)

                return try applyDuplicateFilter(Track.all())
                    .filter(trackIds.contains(Track.Columns.trackId))
                    .fetchAll(db)
            }
        } catch {
            Logger.error("Failed to get tracks by filter type containing: \(error)")
            return []
        }
    }

    // MARK: - Entity Queries (for Home tab)

    /// Get all artist entities without loading tracks
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

    /// Get all album entities without loading tracks
    func getAlbumEntities() -> [AlbumEntity] {
        do {
            return try dbQueue.read { db in
                let albums = try Album
                    .filter(Album.Columns.totalTracks > 0)
                    .order(Album.Columns.sortTitle)
                    .fetchAll(db)
                
                return try albums.map { album in
                    let albumId = album.id ?? 0
                    
                    // Calculate total duration for this album
                    let totalDuration = try Track
                        .filter(Track.Columns.albumId == albumId)
                        .filter(Track.Columns.isDuplicate == false)
                        .select(sum(Track.Columns.duration))
                        .fetchOne(db) ?? 0.0

                    // Fetch primary artist name for this album (if any)
                    let primaryArtistName: String? = try AlbumArtist
                        .filter(AlbumArtist.Columns.albumId == albumId)
                        .filter(AlbumArtist.Columns.role == "primary")
                        .order(AlbumArtist.Columns.position)
                        .fetchOne(db)
                        .flatMap { albumArtist in
                            try Artist
                                .filter(Artist.Columns.id == albumArtist.artistId)
                                .fetchOne(db)
                        }?
                        .name

                    return AlbumEntity(
                        name: album.title,
                        trackCount: album.totalTracks ?? 0,
                        artworkData: album.artworkData,
                        albumId: album.id,
                        year: album.releaseYear.map { String($0) } ?? "",
                        duration: totalDuration,
                        artistName: primaryArtistName
                    )
                }
            }
        } catch {
            Logger.error("Failed to get album entities: \(error)")
            return []
        }
    }

    /// Get tracks for a specific artist entity
    func getTracksForArtistEntity(_ artistName: String) -> [Track] {
        do {
            // First fetch the tracks
            var tracks = try dbQueue.read { db in
                // First find the artist
                let normalizedName = ArtistParser.normalizeArtistName(artistName)
                guard let artist = try Artist
                    .filter((Artist.Columns.name == artistName) || (Artist.Columns.normalizedName == normalizedName))
                    .fetchOne(db),
                    let artistId = artist.id else {
                    return [Track]()
                }
                
                // Get all track IDs for this artist
                let trackIds = try TrackArtist
                    .filter(TrackArtist.Columns.artistId == artistId)
                    .select(TrackArtist.Columns.trackId, as: Int64.self)
                    .fetchAll(db)
                
                // Fetch the tracks
                return try applyDuplicateFilter(Track.all())
                    .filter(trackIds.contains(Track.Columns.trackId))
                    .order(Track.Columns.album, Track.Columns.trackNumber)
                    .fetchAll(db)
            }
            
            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("Failed to get tracks for artist entity: \(error)")
            return []
        }
    }

    /// Get tracks for a specific album entity using album ID
    func getTracksForAlbumEntity(_ albumEntity: AlbumEntity) -> [Track] {
        do {
            // First fetch the tracks
            var tracks = try dbQueue.read { db in
                // If we have the album ID, use it directly
                if let albumId = albumEntity.albumId {
                    return try applyDuplicateFilter(Track.all())
                        .filter(Track.Columns.albumId == albumId)
                        .order(Track.Columns.discNumber, Track.Columns.trackNumber)
                        .fetchAll(db)
                } else {
                    // Fallback to name-based search if no album ID is present
                    let normalizedTitle = albumEntity.name.lowercased()
                        .replacingOccurrences(of: " - ", with: " ")
                        .replacingOccurrences(of: "  ", with: " ")
                        .replacingOccurrences(of: "the ", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Find album by normalized title only (not by artist anymore)
                    guard let album = try Album
                        .filter(Album.Columns.normalizedTitle == normalizedTitle)
                        .fetchOne(db),
                          let albumId = album.id else {
                        Logger.warning("No album found for entity: \(albumEntity.name)")
                        return [Track]()
                    }
                    
                    // Get tracks for this album
                    return try applyDuplicateFilter(Track.all())
                        .filter(Track.Columns.albumId == albumId)
                        .order(Track.Columns.discNumber, Track.Columns.trackNumber)
                        .fetchAll(db)
                }
            }

            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("Failed to get tracks for album entity: \(error)")
            return []
        }
    }

    // MARK: - Quick Count Methods

    func getArtistCount() -> Int {
        do {
            return try dbQueue.read { db in
                try Artist
                    .filter(Artist.Columns.totalTracks > 0)
                    .fetchCount(db)
            }
        } catch {
            Logger.error("Failed to get artist count: \(error)")
            return 0
        }
    }

    func getAlbumCount() -> Int {
        do {
            return try dbQueue.read { db in
                try Album
                    .filter(Album.Columns.totalTracks > 0)
                    .fetchCount(db)
            }
        } catch {
            Logger.error("Failed to get album count: \(error)")
            return 0
        }
    }

    // MARK: - Library Filter Items

    /// Get artist filter items with counts
    func getArtistFilterItems() -> [LibraryFilterItem] {
        do {
            return try dbQueue.read { db in
                let artists = try Artist
                    .order(Artist.Columns.sortName)
                    .fetchAll(db)

                var items: [LibraryFilterItem] = []

                for artist in artists {
                    guard let artistId = artist.id else { continue }

                    // Get track IDs for this artist
                    let trackIds = try TrackArtist
                        .filter(TrackArtist.Columns.artistId == artistId)
                        .filter(TrackArtist.Columns.role == TrackArtist.Role.artist)
                        .select(TrackArtist.Columns.trackId, as: Int64.self)
                        .distinct()
                        .fetchAll(db)

                    // Count only non-duplicate tracks if preference is set
                    let trackCount = try applyDuplicateFilter(Track.all())
                        .filter(trackIds.contains(Track.Columns.trackId))
                        .fetchCount(db)

                    if trackCount > 0 {
                        items.append(LibraryFilterItem(
                            name: artist.name,
                            count: trackCount,
                            filterType: .artists
                        ))
                    }
                }

                // Add unknown placeholder if needed
                let unknownCount = try applyDuplicateFilter(Track.all())
                    .filter(Track.Columns.artist == "Unknown Artist")
                    .fetchCount(db)

                if unknownCount > 0 {
                    items.append(LibraryFilterItem(
                        name: "Unknown Artist",
                        count: unknownCount,
                        filterType: .artists
                    ))
                }

                return items
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
                let artists = try Artist
                    .order(Artist.Columns.sortName)
                    .fetchAll(db)

                var items: [LibraryFilterItem] = []

                for artist in artists {
                    guard let artistId = artist.id else { continue }
                    
                    // Get track IDs for this album-artist
                    let trackIds = try TrackArtist
                        .filter(TrackArtist.Columns.artistId == artistId)
                        .filter(TrackArtist.Columns.role == TrackArtist.Role.albumArtist)
                        .select(TrackArtist.Columns.trackId, as: Int64.self)
                        .distinct()
                        .fetchAll(db)

                    // Count only non-duplicate tracks if preference is set
                    let trackCount = try applyDuplicateFilter(Track.all())
                        .filter(trackIds.contains(Track.Columns.trackId))
                        .fetchCount(db)

                    if trackCount > 0 {
                        items.append(LibraryFilterItem(
                            name: artist.name,
                            count: trackCount,
                            filterType: .albumArtists
                        ))
                    }
                }

                // Add unknown placeholder if needed
                let unknownCount = try applyDuplicateFilter(Track.all())
                    .filter(Track.Columns.albumArtist == "Unknown Album Artist")
                    .fetchCount(db)

                if unknownCount > 0 {
                    items.append(LibraryFilterItem(
                        name: "Unknown Album Artist",
                        count: unknownCount,
                        filterType: .albumArtists
                    ))
                }

                return items
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
                let composers = try Artist
                    .order(Artist.Columns.sortName)
                    .fetchAll(db)

                var items: [LibraryFilterItem] = []

                for composer in composers {
                    guard let composerId = composer.id else { continue }
                    
                    // Get track IDs for this composer
                    let trackIds = try TrackArtist
                        .filter(TrackArtist.Columns.artistId == composerId)
                        .filter(TrackArtist.Columns.role == TrackArtist.Role.composer)
                        .select(TrackArtist.Columns.trackId, as: Int64.self)
                        .distinct()
                        .fetchAll(db)

                    // Count only non-duplicate tracks if preference is set
                    let trackCount = try applyDuplicateFilter(Track.all())
                        .filter(trackIds.contains(Track.Columns.trackId))
                        .fetchCount(db)

                    if trackCount > 0 {
                        items.append(LibraryFilterItem(
                            name: composer.name,
                            count: trackCount,
                            filterType: .composers
                        ))
                    }
                }

                // Add unknown placeholder if needed
                let unknownCount = try applyDuplicateFilter(Track.all())
                    .filter(Track.Columns.composer == "Unknown Composer")
                    .fetchCount(db)

                if unknownCount > 0 {
                    items.append(LibraryFilterItem(
                        name: "Unknown Composer",
                        count: unknownCount,
                        filterType: .composers
                    ))
                }

                return items
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
                let albums = try Album
                    .order(Album.Columns.sortTitle)
                    .fetchAll(db)

                var items: [LibraryFilterItem] = []

                for album in albums {
                    guard let albumId = album.id else { continue }

                    let trackCount = try applyDuplicateFilter(Track.all())
                        .filter(Track.Columns.albumId == albumId)
                        .fetchCount(db)

                    if trackCount > 0 {
                        items.append(LibraryFilterItem(
                            name: album.title,
                            count: trackCount,
                            filterType: .albums
                        ))
                    }
                }

                // Add unknown album if needed
                let unknownCount = try applyDuplicateFilter(Track.all())
                    .filter(Track.Columns.album == "Unknown Album")
                    .filter(Track.Columns.albumId == nil)
                    .fetchCount(db)

                if unknownCount > 0 {
                    items.append(LibraryFilterItem(
                        name: "Unknown Album",
                        count: unknownCount,
                        filterType: .albums
                    ))
                }

                return items
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
                let genres = try Genre
                    .order(Genre.Columns.name)
                    .fetchAll(db)

                var items: [LibraryFilterItem] = []

                for genre in genres {
                    guard let genreId = genre.id else { continue }

                    // Get track IDs for this genre
                    let trackIds = try TrackGenre
                        .filter(TrackGenre.Columns.genreId == genreId)
                        .select(TrackGenre.Columns.trackId, as: Int64.self)
                        .distinct()
                        .fetchAll(db)

                    // Count only non-duplicate tracks if preference is set
                    let trackCount = try applyDuplicateFilter(Track.all())
                        .filter(trackIds.contains(Track.Columns.trackId))
                        .fetchCount(db)

                    if trackCount > 0 {
                        items.append(LibraryFilterItem(
                            name: genre.name,
                            count: trackCount,
                            filterType: .genres
                        ))
                    }
                }

                // Add unknown genre if needed
                let unknownCount = try applyDuplicateFilter(Track.all())
                    .filter(Track.Columns.genre == "Unknown Genre")
                    .fetchCount(db)

                if unknownCount > 0 {
                    items.append(LibraryFilterItem(
                        name: "Unknown Genre",
                        count: unknownCount,
                        filterType: .genres
                    ))
                }

                return items
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
                // Get all tracks with valid years
                let tracks = try applyDuplicateFilter(Track.all())
                    .filter(Track.Columns.year != "")
                    .filter(Track.Columns.year != "Unknown Year")
                    .fetchAll(db)
                
                // Group by decade
                var decadeCounts: [String: Int] = [:]
                
                for track in tracks {
                    // Parse year to get decade
                    if let yearInt = Int(track.year.prefix(4)) {
                        let decade = (yearInt / 10) * 10
                        let decadeString = "\(decade)s"
                        decadeCounts[decadeString, default: 0] += 1
                    }
                }
                
                // Convert to LibraryFilterItems and sort by decade (descending)
                let items = decadeCounts.map { decade, count in
                    LibraryFilterItem(name: decade, count: count, filterType: .decades)
                }.sorted { item1, item2 in
                    // Extract decade year for proper numeric sorting
                    let decade1 = Int(item1.name.dropLast()) ?? 0
                    let decade2 = Int(item2.name.dropLast()) ?? 0
                    return decade1 > decade2
                }
                
                return items
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
                let years = try applyDuplicateFilter(Track.all())
                    .select(Track.Columns.year, as: String.self)
                    .filter(Track.Columns.year != "")
                    .filter(Track.Columns.year != "Unknown Year")
                    .distinct()
                    .order(Track.Columns.year.desc)
                    .fetchAll(db)

                var items: [LibraryFilterItem] = []

                for year in years {
                    let count = try applyDuplicateFilter(Track.all())
                        .filter(Track.Columns.year == year)
                        .fetchCount(db)

                    items.append(LibraryFilterItem(
                        name: year,
                        count: count,
                        filterType: .years
                    ))
                }

                return items
            }
        } catch {
            Logger.error("Failed to get year filter items: \(error)")
            return []
        }
    }

    func getAllTracks() -> [Track] {
        do {
            var tracks = try dbQueue.read { db in
                try Track.lightweightRequest()
                    .order(Track.Columns.title)
                    .fetchAll(db)
            }

            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("Failed to fetch all tracks: \(error)")
            return []
        }
    }

    func getTracksForFolder(_ folderId: Int64) -> [Track] {
        do {
            var tracks = try dbQueue.read { db in
                try Track.lightweightRequest()
                    .filter(Track.Columns.folderId == folderId)
                    .order(Track.Columns.title)
                    .fetchAll(db)
            }
            
            populateAlbumArtworkForTracks(&tracks)
            
            return tracks
        } catch {
            Logger.error("Failed to fetch tracks for folder: \(error)")
            return []
        }
    }
    
    /// Get artist ID by name
    func getArtistId(for artistName: String) -> Int64? {
        do {
            return try dbQueue.read { db in
                let normalizedName = ArtistParser.normalizeArtistName(artistName)
                return try Artist
                    .filter((Artist.Columns.name == artistName) || (Artist.Columns.normalizedName == normalizedName))
                    .fetchOne(db)?
                    .id
            }
        } catch {
            Logger.error("Failed to get artist ID: \(error)")
            return nil
        }
    }
    
    /// Get album by title
    func getAlbumByTitle(_ title: String) -> Album? {
        do {
            return try dbQueue.read { db in
                try Album
                    .filter(Album.Columns.title == title)
                    .fetchOne(db)
            }
        } catch {
            Logger.error("Failed to get album by title: \(error)")
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    func trackExists(withId trackId: Int64) -> Bool {
        do {
            return try dbQueue.read { db in
                try Track.filter(Track.Columns.trackId == trackId).fetchCount(db) > 0
            }
        } catch {
            Logger.error("Failed to check track existence: \(error)")
            return false
        }
    }

    /// Apply duplicate filtering to a Track query if the user preference is enabled
    func applyDuplicateFilter(_ query: QueryInterfaceRequest<Track>) -> QueryInterfaceRequest<Track> {
        let hideDuplicates = UserDefaults.standard.bool(forKey: "hideDuplicateTracks")
        
        if hideDuplicates {
            return query.filter(Track.Columns.isDuplicate == false)
        }
        
        return query
    }
}
