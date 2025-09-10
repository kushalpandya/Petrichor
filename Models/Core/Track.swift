import Foundation
import GRDB
import AppKit

struct Track: Identifiable, Equatable, Hashable, FetchableRecord, PersistableRecord {
    let id = UUID()
    var trackId: Int64?
    let url: URL
    
    // Core metadata for display
    var title: String
    var artist: String
    var album: String
    var duration: Double
    
    // File properties
    let format: String
    var folderId: Int64?
    
    // Navigation fields (for "Go to" functionality)
    var albumArtist: String?
    var composer: String
    var genre: String
    var year: String
    
    // User interaction state
    var isFavorite: Bool = false
    var playCount: Int = 0
    var lastPlayedDate: Date?
    
    // Sorting fields
    var trackNumber: Int?
    var discNumber: Int?
    
    // State tracking
    var isMetadataLoaded: Bool = false
    var isDuplicate: Bool = false
    var dateAdded: Date?
    
    // Album reference (for artwork lookup)
    var albumId: Int64?
    
    // Transient properties for album artwork (populated separately)
    var albumArtworkData: Data?
    private static var artworkCache = NSCache<NSString, NSData>()
    
    var filename: String {
        url.lastPathComponent
    }
    
    var albumArtworkSmall: Data? {
        get {
            guard let original = albumArtworkData else { return nil }
            
            let cacheKey = "\(id.uuidString)-small" as NSString
            if let cached = Track.artworkCache.object(forKey: cacheKey) {
                return cached as Data
            }
            
            if let jpegData = ImageResizer.resizeImage(from: original, to: ImageResizer.Size.small) {
                Track.artworkCache.setObject(jpegData as NSData, forKey: cacheKey)
                return jpegData
            }
            return nil
        }
        set {
            let cacheKey = "\(id.uuidString)-small" as NSString
            if let data = newValue {
                Track.artworkCache.setObject(data as NSData, forKey: cacheKey)
            }
        }
    }

    var albumArtworkMedium: Data? {
        get {
            guard let original = albumArtworkData else { return nil }
            
            let cacheKey = "\(id.uuidString)-medium" as NSString
            if let cached = Track.artworkCache.object(forKey: cacheKey) {
                return cached as Data
            }
            
            if let jpegData = ImageResizer.resizeImage(from: original, to: ImageResizer.Size.medium) {
                Track.artworkCache.setObject(jpegData as NSData, forKey: cacheKey)
                return jpegData
            }
            return nil
        }
        set {
            let cacheKey = "\(id.uuidString)-medium" as NSString
            if let data = newValue {
                Track.artworkCache.setObject(data as NSData, forKey: cacheKey)
            }
        }
    }

    var albumArtworkLarge: Data? {
        get {
            guard let original = albumArtworkData else { return nil }
            
            let cacheKey = "\(id.uuidString)-large" as NSString
            if let cached = Track.artworkCache.object(forKey: cacheKey) {
                return cached as Data
            }
            
            if let jpegData = ImageResizer.resizeImage(from: original, to: ImageResizer.Size.large) {
                Track.artworkCache.setObject(jpegData as NSData, forKey: cacheKey)
                return jpegData
            }
            return nil
        }
        set {
            let cacheKey = "\(id.uuidString)-large" as NSString
            if let data = newValue {
                Track.artworkCache.setObject(data as NSData, forKey: cacheKey)
            }
        }
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
        static let title = Column("title")
        static let artist = Column("artist")
        static let album = Column("album")
        static let composer = Column("composer")
        static let genre = Column("genre")
        static let year = Column("year")
        static let duration = Column("duration")
        static let format = Column("format")
        static let dateAdded = Column("date_added")
        static let isFavorite = Column("is_favorite")
        static let playCount = Column("play_count")
        static let lastPlayedDate = Column("last_played_date")
        static let albumArtist = Column("album_artist")
        static let trackNumber = Column("track_number")
        static let discNumber = Column("disc_number")
        static let albumId = Column("album_id")
        static let isDuplicate = Column("is_duplicate")
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
        dateAdded = row[Columns.dateAdded]
        isFavorite = row[Columns.isFavorite]
        playCount = row[Columns.playCount]
        lastPlayedDate = row[Columns.lastPlayedDate]
        
        // Navigation fields
        albumArtist = row[Columns.albumArtist]
        
        // Sorting fields
        trackNumber = row[Columns.trackNumber]
        discNumber = row[Columns.discNumber]
        
        // State
        isDuplicate = row[Columns.isDuplicate] ?? false
        
        // Album reference
        albumId = row[Columns.albumId]
        
        isMetadataLoaded = true
    }
    
    // MARK: - PersistableRecord
    
    func encode(to container: inout PersistenceContainer) throws {
        // Only encode the lightweight fields when saving
        container[Columns.trackId] = trackId
        container[Columns.folderId] = folderId
        container[Columns.path] = url.path
        container[Columns.title] = title
        container[Columns.artist] = artist
        container[Columns.album] = album
        container[Columns.composer] = composer
        container[Columns.genre] = genre
        container[Columns.year] = year
        container[Columns.duration] = duration
        container[Columns.format] = format
        container[Columns.dateAdded] = dateAdded ?? Date()
        container[Columns.isFavorite] = isFavorite
        container[Columns.playCount] = playCount
        container[Columns.lastPlayedDate] = lastPlayedDate
        container[Columns.albumArtist] = albumArtist
        container[Columns.trackNumber] = trackNumber
        container[Columns.discNumber] = discNumber
        container[Columns.albumId] = albumId
    }
    
    // MARK: - Relationships
    
    static let folder = belongsTo(Folder.self)
    
    var folder: QueryInterfaceRequest<Folder> {
        request(for: Track.folder)
    }
    
    // MARK: - Equatable
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Helper Methods

extension Track {
    /// Get a display-friendly artist name
    var displayArtist: String {
        albumArtist ?? artist
    }
    
    /// Get formatted duration string
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    /// Computed property for artwork
    var artworkData: Data? {
        albumArtworkData
    }
    
    /// Check if this track has album artwork
    var hasArtwork: Bool {
        albumArtworkData != nil
    }
}

// MARK: - Update Helpers

extension Track {
    /// Create a copy with updated favorite status
    func withFavoriteStatus(_ isFavorite: Bool) -> Track {
        var copy = self
        copy.isFavorite = isFavorite
        return copy
    }
    
    /// Create a copy with updated play stats
    func withPlayStats(playCount: Int, lastPlayedDate: Date?) -> Track {
        var copy = self
        copy.playCount = playCount
        copy.lastPlayedDate = lastPlayedDate
        return copy
    }
}

// MARK: - Database Query Helpers

extension Track {
    /// Fetch only the columns needed for lightweight Track
    static var lightweightSelection: [Column] {
        [
            Columns.trackId,
            Columns.folderId,
            Columns.path,
            Columns.title,
            Columns.artist,
            Columns.album,
            Columns.composer,
            Columns.genre,
            Columns.year,
            Columns.duration,
            Columns.format,
            Columns.dateAdded,
            Columns.isFavorite,
            Columns.playCount,
            Columns.lastPlayedDate,
            Columns.albumArtist,
            Columns.trackNumber,
            Columns.discNumber,
            Columns.albumId,
            Columns.isDuplicate
        ]
    }
    
    /// Request for fetching lightweight tracks
    static func lightweightRequest() -> QueryInterfaceRequest<Track> {
        Track
            .select(lightweightSelection)
            .filter(Columns.isDuplicate == false)
    }
}

// MARK: - Duplicate Detection

extension Track {
    /// Generate a key for duplicate detection
    var duplicateKey: String {
        let normalizedTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAlbum = album.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedYear = year.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Round duration to nearest 2 seconds to handle slight variations
        let roundedDuration = Int((duration / 2.0).rounded()) * 2
        
        return "\(normalizedTitle)|\(normalizedAlbum)|\(normalizedYear)|\(roundedDuration)"
    }
}
// MARK: - Full Track Loading

extension Track {
    /// Fetch the complete FullTrack record from database
    /// - Parameter db: Database connection
    /// - Returns: FullTrack with all metadata, or nil if not found
    func fullTrack(db: Database) throws -> FullTrack? {
        guard let trackId = trackId else { return nil }
        
        return try FullTrack
            .filter(FullTrack.Columns.trackId == trackId)
            .fetchOne(db)
    }
    
    /// Async version for fetching FullTrack
    /// - Parameter dbQueue: Database queue
    /// - Returns: FullTrack with all metadata, or nil if not found
    func fullTrack(using dbQueue: DatabaseQueue) async throws -> FullTrack? {
        guard let trackId = trackId else { return nil }
        
        return try await dbQueue.read { db in
            try FullTrack
                .filter(FullTrack.Columns.trackId == trackId)
                .fetchOne(db)
        }
    }
}
