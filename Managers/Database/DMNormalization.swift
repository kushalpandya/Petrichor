//
// DatabaseManager class extension
//
// This extension contains the data normalization methods which clean up any missing details in tracks,
// isolate duplicate album names as well as update track metadata across different db tables for album,
// artist, etc.
//

import Foundation
import GRDB

extension DatabaseManager {
    // MARK: - Artist Management

    /// Find or create an artist by name
    func findOrCreateArtist(_ name: String, in db: Database) throws -> Artist {
        let normalizedName = ArtistParser.normalizeArtistName(name)

        // Try to find existing artist
        if let existing = try Artist
            .filter(Artist.Columns.normalizedName == normalizedName)
            .fetchOne(db) {
            return existing
        }

        // Create new artist
        let artist = Artist(name: name)
        try artist.insert(db)
        return artist
    }

    /// Process all artists for a track (artists, composers, album artists)
    func processTrackArtists(_ track: FullTrack, metadata: TrackMetadata, in db: Database) throws {
        guard let trackId = track.trackId else { return }

        // Process main artists
        if !track.artist.isEmpty && track.artist != "Unknown Artist" {
            try processArtistsForField(
                track.artist,
                trackId: trackId,
                role: TrackArtist.Role.artist,
                in: db
            )
        }

        // Process composers
        if !track.composer.isEmpty && track.composer != "Unknown Composer" {
            try processArtistsForField(
                track.composer,
                trackId: trackId,
                role: TrackArtist.Role.composer,
                in: db
            )
        }

        // Process album artists
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            try processArtistsForField(
                albumArtist,
                trackId: trackId,
                role: TrackArtist.Role.albumArtist,
                in: db
            )
        }
    }

    private func processArtistsForField(_ field: String, trackId: Int64, role: String, in db: Database) throws {
        let artistNames = ArtistParser.parse(field)

        for (index, artistName) in artistNames.enumerated() {
            let artist = try findOrCreateArtist(artistName, in: db)

            guard let artistId = artist.id else { continue }

            // Create track-artist relationship
            let trackArtist = TrackArtist(
                trackId: trackId,
                artistId: artistId,
                role: role,
                position: index
            )

            try trackArtist.insert(db)
        }
    }

    /// Update artist artwork
    func updateArtistArtwork(_ artistId: Int64, artworkData: Data?, in db: Database) throws {
        guard let artworkData = artworkData else { return }

        // Check if artist already has artwork
        guard let artist = try Artist.fetchOne(db, key: artistId),
              artist.artworkData == nil else { return }

        // Update artwork
        artist.artworkData = artworkData
        artist.updatedAt = Date()
        try artist.update(db)
    }

    // MARK: - Album Management

    /// Find or create an album with better duplicate prevention
    func findOrCreateAlbum(_ title: String, albumArtist: String?, in db: Database) throws -> Album {
        let normalizedTitle = title.lowercased()
            .replacingOccurrences(of: " - ", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: "the ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let query = Album.filter(Album.Columns.normalizedTitle == normalizedTitle)
        
        if let albumArtist = albumArtist, !albumArtist.isEmpty, albumArtist != "Unknown Artist" {
            let normalizedArtistName = ArtistParser.normalizeArtistName(albumArtist)
            if let artist = try Artist
                .filter((Artist.Columns.name == albumArtist) || (Artist.Columns.normalizedName == normalizedArtistName))
                .fetchOne(db),
               let artistId = artist.id {
                // Find albums that have this artist as an album artist
                let albumIdsWithArtist = try AlbumArtist
                    .filter(AlbumArtist.Columns.artistId == artistId)
                    .select(AlbumArtist.Columns.albumId, as: Int64.self)
                    .fetchSet(db)
                
                // Filter to albums with matching title AND this artist
                if let existingAlbum = try Album
                    .filter(Album.Columns.normalizedTitle == normalizedTitle)
                    .filter(albumIdsWithArtist.contains(Album.Columns.id))
                    .fetchOne(db) {
                    return existingAlbum
                }
            }
        } else {
            // No album artist info, fall back to title-only matching
            if let existingAlbum = try query.fetchOne(db) {
                return existingAlbum
            }
        }
        
        // No existing album found, create new one
        let album = Album(title: title)
        try album.insert(db)
        
        // If we have an album artist, create the relationship
        if let albumArtist = albumArtist, !albumArtist.isEmpty, albumArtist != "Unknown Artist" {
            let artist = try findOrCreateArtist(albumArtist, in: db)
            if let artistId = artist.id, let albumId = album.id {
                let albumArtist = AlbumArtist(
                    albumId: albumId,
                    artistId: artistId,
                    role: AlbumArtist.Role.primary,
                    position: 0
                )
                try albumArtist.insert(db)
            }
        }
        
        return album
    }

    /// Process album for a track
    func processTrackAlbum(_ track: inout FullTrack, in db: Database) throws {
        guard !track.album.isEmpty && track.album != "Unknown Album" else { return }
        
        // Determine the album artist (prefer albumArtist field, fallback to first artist from multi-artist string)
        let albumArtistName: String?
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty {
            albumArtistName = albumArtist
        } else if !track.artist.isEmpty && track.artist != "Unknown Artist" {
            // Parse the artist field and use the first artist as the album artist
            let artists = ArtistParser.parse(track.artist)
            albumArtistName = artists.first
        } else {
            albumArtistName = nil
        }
        
        let album = try findOrCreateAlbum(track.album, albumArtist: albumArtistName, in: db)
        track.albumId = album.id
        
        // Update album metadata if we have more info
        if let albumId = album.id {
            try updateAlbumMetadata(albumId: albumId, from: track, in: db)
            
            // Process all artists from the track as album artists
            if !track.artist.isEmpty && track.artist != "Unknown Artist" {
                try processAlbumArtists(albumId, artistString: track.artist, in: db)
            }
        }
    }
    
    /// Process all artists for an album
    private func processAlbumArtists(_ albumId: Int64, artistString: String, in db: Database) throws {
        // Parse all artists from the string
        let artistNames = ArtistParser.parse(artistString)
        
        // Get existing album artists
        let existingAlbumArtists = try AlbumArtist
            .filter(AlbumArtist.Columns.albumId == albumId)
            .fetchAll(db)
        
        // Create a set of existing artist IDs for this album
        let existingArtistIds = Set(existingAlbumArtists.map { $0.artistId })
        
        for (index, artistName) in artistNames.enumerated() {
            let artist = try findOrCreateArtist(artistName, in: db)
            
            guard let artistId = artist.id else { continue }
            
            // Skip if this artist is already associated with the album
            if existingArtistIds.contains(artistId) {
                continue
            }
            
            // Determine role - primary for first artist if no artists exist yet
            let role: String
            if existingAlbumArtists.isEmpty && index == 0 {
                role = AlbumArtist.Role.primary
            } else {
                role = AlbumArtist.Role.featured
            }
            
            // Calculate position
            let position = existingAlbumArtists.count + index
            
            // Create album-artist relationship
            let albumArtist = AlbumArtist(
                albumId: albumId,
                artistId: artistId,
                role: role,
                position: position
            )
            
            try albumArtist.insert(db)
        }
    }

    private func updateAlbumMetadata(albumId: Int64, from track: FullTrack, in db: Database) throws {
        guard let album = try Album.fetchOne(db, key: albumId) else { return }

        var needsUpdate = false

        // Update release year if not set
        if album.releaseYear == nil && !track.year.isEmpty && track.year != "Unknown Year" {
            if let year = Int(track.year) {
                album.releaseYear = year
                needsUpdate = true
            }
        }

        // Update release date if not set
        if album.releaseDate == nil && track.releaseDate != nil {
            album.releaseDate = track.releaseDate
            needsUpdate = true
        }

        // Update total tracks/discs if we have more complete info
        if let trackTotal = track.totalTracks,
           let albumTotal = album.totalTracks,
           trackTotal > albumTotal {
            album.totalTracks = trackTotal
            needsUpdate = true
        }

        if let discTotal = track.totalDiscs,
           let albumTotal = album.totalDiscs,
           discTotal > albumTotal {
            album.totalDiscs = discTotal
            needsUpdate = true
        }

        // Copy extended metadata that might be useful
        if album.label == nil, let label = track.extendedMetadata?.label {
            album.label = label
            needsUpdate = true
        }

        if needsUpdate {
            try album.update(db)
        }
    }

    /// Update album artwork
    func updateAlbumArtwork(_ albumId: Int64, artworkData: Data?, in db: Database) throws {
        guard let artworkData = artworkData, !artworkData.isEmpty else { return }

        // Check if album already has artwork, don't overwrite existing artwork
        if let existingArtwork = try Album
            .select(Album.Columns.artworkData)
            .filter(Album.Columns.id == albumId)
            .fetchOne(db)?[Album.Columns.artworkData] as Data?,
           !existingArtwork.isEmpty {
            // Album already has artwork, skip update
            return
        }

        try db.execute(
            sql: "UPDATE albums SET artwork_data = ?, updated_at = ? WHERE id = ? AND artwork_data IS NULL",
            arguments: [artworkData, Date(), albumId]
        )
    }

    // MARK: - Genre Management

    /// Find or create genres for a track
    func processTrackGenres(_ track: FullTrack, in db: Database) throws {
        guard let trackId = track.trackId,
              !track.genre.isEmpty && track.genre != "Unknown Genre" else { return }

        // Genres might be separated by various delimiters
        let genreNames = track.genre
            .split(separator: ";")
            .flatMap { $0.split(separator: "/") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for genreName in genreNames {
            let genre = try findOrCreateGenre(String(genreName), in: db)

            guard let genreId = genre.id else { continue }

            // Create track-genre relationship
            let trackGenre = TrackGenre(trackId: trackId, genreId: genreId)
            try trackGenre.insert(db)
        }
    }

    private func findOrCreateGenre(_ name: String, in db: Database) throws -> Genre {
        if let existing = try Genre
            .filter(Genre.Columns.name == name)
            .fetchOne(db) {
            return existing
        }

        let genre = Genre(name: name)
        try genre.insert(db)
        return genre
    }

    // MARK: - Stats Update

    /// Update artist and album statistics
    func updateEntityStats(in db: Database) throws {
        // Batch update artists
        try updateArtistStats(in: db)

        // Batch update albums
        try updateAlbumStats(in: db)
    }

    /// Update artist stats - for one artist or all if artistId is nil
    func updateArtistStats(artistId: Int64? = nil, in db: Database) throws {
        let artistIds: [Int64]
        
        if let specificId = artistId {
            artistIds = [specificId]
        } else {
            artistIds = try Artist
                .select(Artist.Columns.id, as: Int64.self)
                .fetchAll(db)
        }
        
        for id in artistIds {
            guard let artist = try Artist.fetchOne(db, key: id) else { continue }
            
            artist.totalTracks = try TrackArtist
                .joining(required: TrackArtist.track.filter(Track.Columns.isDuplicate == false))
                .filter(TrackArtist.Columns.artistId == id)
                .filter(TrackArtist.Columns.role == TrackArtist.Role.artist)
                .select(TrackArtist.Columns.trackId, as: Int64.self)
                .distinct()
                .fetchCount(db)

            artist.totalAlbums = try AlbumArtist
                .filter(AlbumArtist.Columns.artistId == id)
                .select(AlbumArtist.Columns.albumId, as: Int64.self)
                .distinct()
                .fetchCount(db)

            artist.updatedAt = Date()
            try artist.update(db)
        }
    }

    /// Update album stats - for one album or all if albumId is nil
    func updateAlbumStats(albumId: Int64? = nil, in db: Database) throws {
        let albumIds: [Int64]
        
        if let specificId = albumId {
            albumIds = [specificId]
        } else {
            albumIds = try Album
                .select(Album.Columns.id, as: Int64.self)
                .fetchAll(db)
        }
        
        for id in albumIds {
            guard let album = try Album.fetchOne(db, key: id) else { continue }
            
            album.totalTracks = try Track
                .filter(Track.Columns.albumId == id)
                .filter(Track.Columns.isDuplicate == false)
                .fetchCount(db)

            album.updatedAt = Date()
            try album.update(db)
        }
    }

    // MARK: - Query Methods for Normalized Data

    /// Get all artists with track counts
    func getAllArtists() throws -> [Artist] {
        try dbQueue.read { db in
            try Artist
                .order(Artist.Columns.sortName)
                .fetchAll(db)
        }
    }

    /// Get all albums with track counts
    func getAllAlbums() throws -> [Album] {
        try dbQueue.read { db in
            try Album
                .order(Album.Columns.sortTitle)
                .fetchAll(db)
        }
    }

    /// Get all genres with track counts
    func getAllGenres() throws -> [Genre] {
        try dbQueue.read { db in
            try Genre
                .order(Genre.Columns.name)
                .fetchAll(db)
        }
    }

    /// Get tracks by artist (including all roles)
    func getTracksByArtist(_ artistId: Int64) throws -> [Track] {
        try dbQueue.read { db in
            let trackIds = try TrackArtist
                .filter(TrackArtist.Columns.artistId == artistId)
                .select(TrackArtist.Columns.trackId, as: Int64.self)
                .fetchAll(db)

            return try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }

    /// Get tracks by album
    func getTracksByAlbum(_ albumId: Int64) throws -> [Track] {
        try dbQueue.read { db in
            try Track
                .filter(Track.Columns.albumId == albumId)
                .order(Track.Columns.discNumber, Track.Columns.trackNumber)
                .fetchAll(db)
        }
    }

    /// Get tracks by genre
    func getTracksByGenre(_ genreId: Int64) throws -> [Track] {
        try dbQueue.read { db in
            let trackIds = try TrackGenre
                .filter(TrackGenre.Columns.genreId == genreId)
                .select(TrackGenre.Columns.trackId, as: Int64.self)
                .fetchAll(db)

            return try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }

    /// Get tracks by decade
    func getTracksByDecade(_ decade: Int) throws -> [Track] {
        try dbQueue.read { db in
            let startYear = String(decade)
            let endYear = String(decade + 9)

            return try Track
                .filter(Track.Columns.year >= startYear)
                .filter(Track.Columns.year <= endYear)
                .filter(Track.Columns.year != "")
                .filter(Track.Columns.year != "Unknown Year")
                .order(Track.Columns.year, Track.Columns.album)
                .fetchAll(db)
        }
    }

    /// Get decade statistics
    func getDecadeStats() throws -> [(decade: Int, count: Int)] {
        try dbQueue.read { db in
            // First, get all valid years
            let validYears = try Track
                .select(Track.Columns.year, as: String.self)
                .filter(Track.Columns.year != "")
                .filter(Track.Columns.year != "Unknown Year")
                .distinct()
                .fetchAll(db)

            // Group by decade
            var decadeStats: [Int: Int] = [:]

            for yearString in validYears {
                guard let year = Int(yearString), year > 0 else { continue }
                let decade = (year / 10) * 10

                let count = try Track
                    .filter(Track.Columns.year == yearString)
                    .fetchCount(db)

                decadeStats[decade, default: 0] += count
            }

            // Convert to array and sort
            return decadeStats
                .map { (decade: $0.key, count: $0.value) }
                .sorted { $0.decade > $1.decade }
        }
    }
}
