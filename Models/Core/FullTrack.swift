import Foundation
import GRDB

struct FullTrack: Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    let id = UUID()
    var trackId: Int64?
    let url: URL
    
    // Core metadata
    var title: String
    var artist: String
    var album: String
    var composer: String
    var genre: String
    var year: String
    var duration: Double
    var trackArtworkData: Data?
    var albumArtworkData: Data?
    var isMetadataLoaded: Bool = false
    var isFavorite: Bool = false
    var playCount: Int = 0
    var lastPlayedDate: Date?
    
    // File properties
    let format: String
    var folderId: Int64?
    
    // Additional metadata
    var albumArtist: String?
    var trackNumber: Int?
    var totalTracks: Int?
    var discNumber: Int?
    var totalDiscs: Int?
    var rating: Int?
    var compilation: Bool = false
    var releaseDate: String?
    var originalReleaseDate: String?
    var bpm: Int?
    var mediaType: String?
    var bitrate: Int?
    var sampleRate: Int?
    var channels: Int?
    var codec: String?
    var bitDepth: Int?
    var fileSize: Int64?
    var dateAdded: Date?
    var dateModified: Date?
    
    // Duplicate tracking
    var isDuplicate: Bool = false
    var primaryTrackId: Int64?
    var duplicateGroupId: String?
    
    // Sort fields
    var sortTitle: String?
    var sortArtist: String?
    var sortAlbum: String?
    var sortAlbumArtist: String?
    
    // Extended metadata
    var extendedMetadata: ExtendedMetadata?
    
    // Album reference
    var albumId: Int64?
    
    // Computed property for artwork
    var artworkData: Data? {
        // Prefer album artwork if available
        if let albumArtwork = albumArtworkData {
            return albumArtwork
        }
        // Fall back to track's own artwork
        return trackArtworkData
    }
    
    // MARK: - Initialization
    
    init(url: URL) {
        self.url = url
        
        // Default values - these will be overridden by metadata
        self.title = url.deletingPathExtension().lastPathComponent
        self.artist = "Unknown Artist"
        self.album = "Unknown Album"
        self.composer = "Unknown Composer"
        self.genre = "Unknown Genre"
        self.year = "Unknown Year"
        self.duration = 0
        self.format = url.pathExtension
        self.extendedMetadata = ExtendedMetadata()
    }
    
    // MARK: - DB Configuration
    
    static let databaseTableName = "tracks"
    
    static let columnMap: [String: Column] = [
        "artist": Columns.artist,
        "album": Columns.album,
        "album_artist": Columns.albumArtist,
        "composer": Columns.composer,
        "genre": Columns.genre,
        "year": Columns.year
    ]
    
    enum Columns {
        static let trackId = Column("id")
        static let folderId = Column("folder_id")
        static let path = Column("path")
        static let filename = Column("filename")
        static let title = Column("title")
        static let artist = Column("artist")
        static let album = Column("album")
        static let composer = Column("composer")
        static let genre = Column("genre")
        static let year = Column("year")
        static let duration = Column("duration")
        static let format = Column("format")
        static let trackArtworkData = Column("track_artwork_data")
        static let dateAdded = Column("date_added")
        static let isFavorite = Column("is_favorite")
        static let playCount = Column("play_count")
        static let lastPlayedDate = Column("last_played_date")
        static let albumArtist = Column("album_artist")
        static let trackNumber = Column("track_number")
        static let totalTracks = Column("total_tracks")
        static let discNumber = Column("disc_number")
        static let totalDiscs = Column("total_discs")
        static let rating = Column("rating")
        static let compilation = Column("compilation")
        static let releaseDate = Column("release_date")
        static let originalReleaseDate = Column("original_release_date")
        static let bpm = Column("bpm")
        static let mediaType = Column("media_type")
        static let bitrate = Column("bitrate")
        static let sampleRate = Column("sample_rate")
        static let channels = Column("channels")
        static let codec = Column("codec")
        static let bitDepth = Column("bit_depth")
        static let fileSize = Column("file_size")
        static let dateModified = Column("date_modified")
        static let isDuplicate = Column("is_duplicate")
        static let primaryTrackId = Column("primary_track_id")
        static let duplicateGroupId = Column("duplicate_group_id")
        static let sortTitle = Column("sort_title")
        static let sortArtist = Column("sort_artist")
        static let sortAlbum = Column("sort_album")
        static let sortAlbumArtist = Column("sort_album_artist")
        static let albumId = Column("album_id")
        static let extendedMetadata = Column("extended_metadata")
    }
    
    // MARK: - FetchableRecord
    
    init(row: Row) throws {
        // Extract path and create URL
        let path: String = row[Columns.path]
        self.url = URL(fileURLWithPath: path)
        self.format = row[Columns.format]
        
        // Core properties
        trackId = row[Columns.trackId]
        folderId = row[Columns.folderId]
        title = row[Columns.title]
        artist = row[Columns.artist]
        album = row[Columns.album]
        composer = row[Columns.composer]
        genre = row[Columns.genre]
        year = row[Columns.year]
        duration = row[Columns.duration]
        trackArtworkData = row[Columns.trackArtworkData]
        dateAdded = row[Columns.dateAdded]
        isFavorite = row[Columns.isFavorite]
        playCount = row[Columns.playCount]
        lastPlayedDate = row[Columns.lastPlayedDate]
        
        // Additional metadata
        albumArtist = row[Columns.albumArtist]
        trackNumber = row[Columns.trackNumber]
        totalTracks = row[Columns.totalTracks]
        discNumber = row[Columns.discNumber]
        totalDiscs = row[Columns.totalDiscs]
        rating = row[Columns.rating]
        compilation = row[Columns.compilation] ?? false
        releaseDate = row[Columns.releaseDate]
        originalReleaseDate = row[Columns.originalReleaseDate]
        bpm = row[Columns.bpm]
        mediaType = row[Columns.mediaType]
        bitrate = row[Columns.bitrate]
        sampleRate = row[Columns.sampleRate]
        channels = row[Columns.channels]
        codec = row[Columns.codec]
        bitDepth = row[Columns.bitDepth]
        fileSize = row[Columns.fileSize]
        dateModified = row[Columns.dateModified]
        
        // Duplicate tracking
        isDuplicate = row[Columns.isDuplicate] ?? false
        primaryTrackId = row[Columns.primaryTrackId]
        duplicateGroupId = row[Columns.duplicateGroupId]
        
        // Sort fields
        sortTitle = row[Columns.sortTitle]
        sortArtist = row[Columns.sortArtist]
        sortAlbum = row[Columns.sortAlbum]
        sortAlbumArtist = row[Columns.sortAlbumArtist]
        
        // Album reference
        albumId = row[Columns.albumId]
        
        // Extended metadata
        let extendedMetadataJSON: String? = row[Columns.extendedMetadata]
        extendedMetadata = ExtendedMetadata.fromJSON(extendedMetadataJSON)
        
        // Mark as loaded
        isMetadataLoaded = true
    }
    
    // MARK: - PersistableRecord
    
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.trackId] = trackId
        container[Columns.folderId] = folderId
        container[Columns.path] = url.path
        container[Columns.filename] = url.lastPathComponent
        container[Columns.title] = title
        container[Columns.artist] = artist
        container[Columns.album] = album
        container[Columns.composer] = composer
        container[Columns.genre] = genre
        container[Columns.year] = year
        container[Columns.duration] = duration
        container[Columns.format] = format
        container[Columns.dateAdded] = dateAdded ?? Date()
        container[Columns.trackArtworkData] = trackArtworkData
        container[Columns.isFavorite] = isFavorite
        container[Columns.playCount] = playCount
        container[Columns.lastPlayedDate] = lastPlayedDate
        container[Columns.albumArtist] = albumArtist
        container[Columns.trackNumber] = trackNumber
        container[Columns.totalTracks] = totalTracks
        container[Columns.discNumber] = discNumber
        container[Columns.totalDiscs] = totalDiscs
        container[Columns.rating] = rating
        container[Columns.compilation] = compilation
        container[Columns.releaseDate] = releaseDate
        container[Columns.originalReleaseDate] = originalReleaseDate
        container[Columns.bpm] = bpm
        container[Columns.mediaType] = mediaType
        container[Columns.bitrate] = bitrate
        container[Columns.sampleRate] = sampleRate
        container[Columns.channels] = channels
        container[Columns.codec] = codec
        container[Columns.bitDepth] = bitDepth
        container[Columns.fileSize] = fileSize
        container[Columns.dateModified] = dateModified
        container[Columns.isDuplicate] = isDuplicate
        container[Columns.primaryTrackId] = primaryTrackId
        container[Columns.duplicateGroupId] = duplicateGroupId
        container[Columns.sortTitle] = sortTitle
        container[Columns.sortArtist] = sortArtist
        container[Columns.sortAlbum] = sortAlbum
        container[Columns.sortAlbumArtist] = sortAlbumArtist
        container[Columns.albumId] = albumId
        
        // Save extended metadata as JSON
        container[Columns.extendedMetadata] = extendedMetadata?.toJSON()
    }
    
    // Update if exists based on path
    mutating func didInsert(_ inserted: InsertionSuccess) {
        trackId = inserted.rowID
    }
    
    // MARK: - Associations
    
    static let folder = belongsTo(Folder.self)
    static let album = belongsTo(Album.self, using: ForeignKey(["album_id"]))
    static let trackArtists = hasMany(TrackArtist.self)
    static let artists = hasMany(Artist.self, through: trackArtists, using: TrackArtist.artist)
    static let genres = hasMany(Genre.self, through: hasMany(TrackGenre.self), using: TrackGenre.genre)
    
    var folder: QueryInterfaceRequest<Folder> {
        request(for: FullTrack.folder)
    }
    
    var artists: QueryInterfaceRequest<Artist> {
        request(for: FullTrack.artists)
    }
    
    var genres: QueryInterfaceRequest<Genre> {
        request(for: FullTrack.genres)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: FullTrack, rhs: FullTrack) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Sorting support
    
    var albumArtistForSorting: String {
        albumArtist ?? ""
    }
    
    // MARK: - Duplicate Detection
    
    /// Generate a normalized key for duplicate detection
    var duplicateKey: String {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Round duration to nearest 2 seconds to handle slight variations
        let roundedDuration = Int((duration / 2.0).rounded()) * 2
        
        return "\(normalizedTitle)|\(normalizedAlbum)|\(normalizedYear)|\(roundedDuration)"
    }
    
    /// Check if this track is a duplicate candidate of another track
    func isDuplicateOf(_ other: FullTrack) -> Bool {
        // Must have valid durations
        guard duration > 0, other.duration > 0 else { return false }
        
        // Check if durations are within 2 seconds of each other
        let durationDiff = abs(duration - other.duration)
        guard durationDiff <= 2.0 else { return false }
        
        // Compare normalized metadata
        return duplicateKey == other.duplicateKey
    }
}

// MARK: - Quality Scoring

extension FullTrack {
    /// Determines if the track is in a lossless format
    var isLossless: Bool {
        let formatLower = format.lowercased()

        let losslessFormats: Set<String> = [
            // Lossless PCM
            "flac", "alac", "wav", "aiff", "aif",
            // Lossless compressed
            "ape", "wv", "tta",
            // DSD formats
            "dsf", "dff",
            // Legacy lossless
            "au",
            // Module/tracker formats
            "mod", "it", "s3m", "xm"
        ]
        
        return losslessFormats.contains(formatLower)
    }

    /// Calculate a quality score for duplicate detection
    /// Higher score = better quality
    var qualityScore: Int {
        var score = 0
        
        let formatExtension = format.lowercased()
        let bitrateValue = bitrate ?? 0
        
        // Format scoring (lossless > high bitrate lossy > low bitrate)
        if isLossless {
            switch formatExtension {
            case "dsf", "dff":
                score += 1200
            default:
                score += 1000
            }
        } else {
            switch formatExtension {
            case "mp3":
                score += bitrateValue >= 320 ? 800 : bitrateValue >= 256 ? 600 : bitrateValue >= 192 ? 400 : 200
            case "aac", "m4a":
                score += bitrateValue >= 256 ? 700 : bitrateValue >= 192 ? 500 : 300
            case "ogg":
                score += bitrateValue >= 192 ? 600 : 400
            case "opus", "oga":
                score += bitrateValue >= 128 ? 650 : 450
            case "mpc":
                score += bitrateValue >= 192 ? 600 : 400
            case "spx":
                score += 300
            default:
                score += 100
            }
        }
        
        // Metadata completeness
        if !title.isEmpty && title != "Unknown Title" { score += 50 }
        if !artist.isEmpty && artist != "Unknown Artist" { score += 50 }
        if !album.isEmpty && album != "Unknown Album" { score += 50 }
        if albumArtist != nil { score += 25 }
        if trackNumber != nil { score += 25 }
        if year != "Unknown Year" { score += 25 }
        if artworkData != nil { score += 100 }
        
        // File characteristics
        if let sampleRate = sampleRate {
            if sampleRate >= 96000 { score += 100 } else if sampleRate >= 48000 { score += 50 }
        }
        
        if let bitDepth = bitDepth {
            if bitDepth >= 24 { score += 50 }
        }
        
        return score
    }
}

// MARK: - Update Helpers

extension FullTrack {
    /// Create a mutable copy with updated favorite status
    func withFavoriteStatus(_ isFavorite: Bool) -> FullTrack {
        var copy = self
        copy.isFavorite = isFavorite
        return copy
    }
    
    /// Create a mutable copy with updated play stats
    func withPlayStats(playCount: Int, lastPlayedDate: Date?) -> FullTrack {
        var copy = self
        copy.playCount = playCount
        copy.lastPlayedDate = lastPlayedDate
        return copy
    }
    
    /// Create a mutable copy with updated album artwork
    func withAlbumArtwork(_ artworkData: Data?) -> FullTrack {
        var copy = self
        copy.albumArtworkData = artworkData
        return copy
    }
}
