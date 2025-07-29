import Foundation
import AppKit
import GRDB

enum PlaylistType: String, Codable {
    case regular
    case smart
}

// Smart playlist criteria
struct SmartPlaylistCriteria: Codable {
    enum MatchType: String, Codable {
        case all
        case any
    }
    
    enum Condition: String, Codable {
        case contains
        case equals
        case startsWith
        case endsWith
        case greaterThan
        case lessThan
    }
    
    struct Rule: Codable {
        let field: String  // "artist", "album", "genre", "year", "playCount", etc.
        let condition: Condition
        let value: String
    }
    
    let matchType: MatchType
    let rules: [Rule]
    let limit: Int?  // Track count limit (e.g., 25 for "Top 25")
    let sortBy: String?  // "dateAdded", "lastPlayed", "playCount", etc.
    let sortAscending: Bool
    
    // Default initializer
    init(
        matchType: MatchType = .all,
        rules: [Rule] = [],
        limit: Int? = nil,
        sortBy: String? = nil,
        sortAscending: Bool = true
    ) {
        self.matchType = matchType
        self.rules = rules
        self.limit = limit
        self.sortBy = sortBy
        self.sortAscending = sortAscending
    }
}

// Cache manager for playlist artwork
private class PlaylistArtworkCache {
    static let shared = PlaylistArtworkCache()
    private var cache: [UUID: (artwork: Data, trackIDs: [UUID])] = [:]
    
    func getCachedArtwork(for playlistID: UUID, currentTrackIDs: [UUID]) -> Data? {
        guard let cached = cache[playlistID] else { return nil }
        return cached.trackIDs == currentTrackIDs ? cached.artwork : nil
    }
    
    func setCachedArtwork(_ artwork: Data, for playlistID: UUID, trackIDs: [UUID]) {
        cache[playlistID] = (artwork, trackIDs)
    }
    
    func clearCache(for playlistID: UUID) {
        cache.removeValue(forKey: playlistID)
    }
}

struct Playlist: Identifiable, FetchableRecord, PersistableRecord {
    let id: UUID
    var name: String
    var tracks: [Track]
    var dateCreated: Date
    var dateModified: Date
    var coverArtworkData: Data?
    let type: PlaylistType
    var trackCount: Int = 0
    var sortOrder: Int = 0
    var isUserEditable: Bool  // Can user delete/rename this playlist?
    var isContentEditable: Bool  // Can user add/remove tracks?
    var smartCriteria: SmartPlaylistCriteria?  // Criteria for smart playlists
    
    // MARK: - Regular Initializers
    
    // Regular playlist initializer
    init(name: String, tracks: [Track] = [], coverArtworkData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.tracks = tracks
        self.dateCreated = Date()
        self.dateModified = Date()
        self.coverArtworkData = coverArtworkData
        self.type = .regular
        self.isUserEditable = true
        self.isContentEditable = true
        self.smartCriteria = nil
    }
    
    // Smart playlist initializer
    init(name: String, criteria: SmartPlaylistCriteria, isUserEditable: Bool = false) {
        self.id = UUID()
        self.name = name
        self.tracks = []
        self.dateCreated = Date()
        self.dateModified = Date()
        self.coverArtworkData = nil
        self.type = .smart
        self.isUserEditable = isUserEditable
        self.isContentEditable = false  // Smart playlists auto-manage their content
        self.smartCriteria = criteria
    }
    
    // Database restoration initializer
    init(
        id: UUID,
        name: String,
        tracks: [Track],
        dateCreated: Date,
        dateModified: Date,
        coverArtworkData: Data?,
        type: PlaylistType,
        isUserEditable: Bool,
        isContentEditable: Bool,
        smartCriteria: SmartPlaylistCriteria?
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.coverArtworkData = coverArtworkData
        self.type = type
        self.isUserEditable = isUserEditable
        self.isContentEditable = isContentEditable
        self.smartCriteria = smartCriteria
    }
    
    // MARK: - GRDB Support
    
    // DB Configuration
    static let databaseTableName = "playlists"
    
    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let type = Column("type")
        static let isUserEditable = Column("is_user_editable")
        static let isContentEditable = Column("is_content_editable")
        static let dateCreated = Column("date_created")
        static let dateModified = Column("date_modified")
        static let coverArtworkData = Column("cover_artwork_data")
        static let smartCriteria = Column("smart_criteria")
        static let sortOrder = Column("sort_order")
    }
    
    // FetchableRecord initializer - used by GRDB when loading from database
    init(row: Row) throws {
        id = UUID(uuidString: row[Columns.id]) ?? UUID()
        name = row[Columns.name]
        type = PlaylistType(rawValue: row[Columns.type]) ?? .regular
        isUserEditable = row[Columns.isUserEditable]
        isContentEditable = row[Columns.isContentEditable]
        dateCreated = row[Columns.dateCreated]
        dateModified = row[Columns.dateModified]
        coverArtworkData = row[Columns.coverArtworkData]
        sortOrder = row[Columns.sortOrder]
        
        // Parse smart criteria
        if let criteriaJSON: String = row[Columns.smartCriteria],
           let data = criteriaJSON.data(using: .utf8) {
            smartCriteria = try? JSONDecoder().decode(SmartPlaylistCriteria.self, from: data)
        } else {
            smartCriteria = nil
        }
        
        // Tracks will be loaded separately with associations
        tracks = []
    }
    
    // PersistableRecord
    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id.uuidString
        container[Columns.name] = name
        container[Columns.type] = type.rawValue
        container[Columns.isUserEditable] = isUserEditable
        container[Columns.isContentEditable] = isContentEditable
        container[Columns.dateCreated] = dateCreated
        container[Columns.dateModified] = dateModified
        container[Columns.coverArtworkData] = coverArtworkData
        container[Columns.sortOrder] = sortOrder
        
        // Encode smart criteria as JSON
        if let criteria = smartCriteria {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(criteria) {
                container[Columns.smartCriteria] = String(data: data, encoding: .utf8)
            }
        }
    }
    
    // Associations
    static let playlistTracks = hasMany(PlaylistTrack.self)
    static let tracks = hasMany(Track.self, through: playlistTracks, using: PlaylistTrack.track)
    
    // MARK: - Business Logic Methods
    
    // Add a track to the playlist (only for regular playlists)
    mutating func addTrack(_ track: Track) {
        guard type == .regular && isContentEditable else { return }
        
        if !tracks.contains(where: { $0.id == track.id }) {
            tracks.append(track)
            dateModified = Date()
            PlaylistArtworkCache.shared.clearCache(for: id)
        }
    }
    
    // Remove a track from the playlist (only for regular playlists)
    mutating func removeTrack(_ track: Track) {
        guard type == .regular && isContentEditable else { return }
        
        Logger.info("Attempting to remove track: \(track.title) with trackId: \(track.trackId ?? -1)")
        Logger.info("Current tracks count: \(tracks.count)")
        
        // Remove by comparing database IDs instead of instance IDs
        if let trackId = track.trackId {
            let beforeCount = tracks.count
            tracks.removeAll { $0.trackId == trackId }
            let afterCount = tracks.count
            Logger.info("Removed \(beforeCount - afterCount) tracks")
        } else {
            // Fallback to UUID comparison if no database ID
            tracks.removeAll { $0.id == track.id }
        }
        
        dateModified = Date()
        PlaylistArtworkCache.shared.clearCache(for: id)
    }
    
    // Move a track within the playlist (only for regular playlists)
    mutating func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard type == .regular && isContentEditable else { return }
        
        guard sourceIndex >= 0, sourceIndex < tracks.count,
              destinationIndex >= 0, destinationIndex < tracks.count,
              sourceIndex != destinationIndex else {
            return
        }
        
        let track = tracks.remove(at: sourceIndex)
        tracks.insert(track, at: destinationIndex)
        dateModified = Date()
        // Only clear cache if moving affects the first 4 tracks
        if sourceIndex < 4 || destinationIndex < 4 {
            PlaylistArtworkCache.shared.clearCache(for: id)
        }
    }
    
    // Clear all tracks from the playlist (only for regular playlists)
    mutating func clearTracks() {
        guard type == .regular && isContentEditable else { return }
        
        tracks.removeAll()
        dateModified = Date()
        PlaylistArtworkCache.shared.clearCache(for: id)
    }
    
    // Calculate total duration of the playlist
    var totalDuration: Double {
        tracks.reduce(0) { $0 + $1.duration }
    }
    
    // Get generated album art of the playlist
    var effectiveCoverArtwork: Data? {
        if let customCover = coverArtworkData {
            return customCover
        }
        
        // For playlists, check cache first
        let currentTrackIDs = tracks.prefix(4).map { $0.id }
        
        if let cachedArtwork = PlaylistArtworkCache.shared.getCachedArtwork(
            for: id,
            currentTrackIDs: currentTrackIDs
        ) {
            return cachedArtwork
        }
        
        // Generate new collage and cache it
        if let newCollage = createCollageArtwork() {
            PlaylistArtworkCache.shared.setCachedArtwork(
                newCollage,
                for: id,
                trackIDs: currentTrackIDs
            )
            return newCollage
        }
        
        return nil
    }
    
    // Get the effective track limit for display
    var trackLimit: Int? {
        smartCriteria?.limit
    }
    
    private func createCollageArtwork() -> Data? {
        // Check if all tracks are from the same album
        let uniqueAlbums = Set(tracks.map { $0.album })
        let isSingleAlbum = uniqueAlbums.count == 1
        
        // If single album or single track, just use the first track's artwork
        if isSingleAlbum || tracks.count == 1 {
            return tracks.first?.artworkData
        }
        
        // Get up to 4 tracks with artwork for collage
        let tracksWithArt = tracks.prefix(4).filter { $0.artworkData != nil }
        
        guard !tracksWithArt.isEmpty else { return nil }
        
        let imageSize: CGFloat = 256
        let collageImage = NSImage(size: NSSize(width: imageSize, height: imageSize))
        
        collageImage.lockFocus()
        
        // Clear background
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: imageSize, height: imageSize).fill()
        
        let count = tracksWithArt.count
        
        // Special handling based on track count
        if count == 1 {
            // Single track - just draw it full size (this case is already handled above, but keeping for safety)
            if let artworkData = tracksWithArt[0].artworkData,
               let image = NSImage(data: artworkData) {
                image.draw(in: NSRect(x: 0, y: 0, width: imageSize, height: imageSize),
                           from: NSRect(origin: .zero, size: image.size),
                           operation: .copy,
                           fraction: 1.0)
            }
        } else {
            // 2 or more tracks - always create 2x2 grid
            let positions = [(0, 0), (1, 0), (0, 1), (1, 1)]  // (col, row) for each quadrant
            
            for (index, (col, row)) in positions.enumerated() {
                let trackIndex: Int
                
                if count == 2 {
                    // For 2 tracks: diagonal pattern (0, 1, 1, 0)
                    trackIndex = (index == 0 || index == 3) ? 0 : 1
                } else {
                    // For 3+ tracks: use available tracks, repeating if necessary
                    trackIndex = index % count
                }
                
                guard let artworkData = tracksWithArt[trackIndex].artworkData,
                      let image = NSImage(data: artworkData) else { continue }
                
                let destRect = NSRect(
                    x: CGFloat(col) * imageSize / 2,
                    y: CGFloat(row) * imageSize / 2,
                    width: imageSize / 2,
                    height: imageSize / 2
                )
                
                image.draw(in: destRect,
                           from: NSRect(origin: .zero, size: image.size),
                           operation: .copy,
                           fraction: 1.0)
            }
        }
        
        collageImage.unlockFocus()
        
        // Convert to PNG data
        guard let tiffData = collageImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return pngData
    }
}

// Extension to format the duration for display
extension Playlist {
    // Format the total duration as a string (HH:MM:SS)
    var formattedTotalDuration: String {
        let totalSeconds = Int(totalDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: StringFormat.hhmmss, hours, minutes, seconds)
        } else {
            return String(format: StringFormat.mmss, minutes, seconds)
        }
    }
}

// Extension for creating default smart playlists
extension Playlist {
    static func createDefaultSmartPlaylists() -> [Playlist] {
        [
            // Favorites playlist - sorted by date added
            Playlist(
                name: DefaultPlaylists.favorites,
                criteria: SmartPlaylistCriteria(
                    rules: [
                        SmartPlaylistCriteria.Rule(
                            field: "isFavorite",
                            condition: .equals,
                            value: "true"
                        )
                    ],
                    sortBy: nil, // No sorting - will maintain order as added
                    sortAscending: true
                ),
                isUserEditable: false
            ),
            
            // Top 25 Most Played - already correct
            Playlist(
                name: DefaultPlaylists.mostPlayed,
                criteria: SmartPlaylistCriteria(
                    rules: [
                        SmartPlaylistCriteria.Rule(
                            field: "playCount",
                            condition: .greaterThan,
                            value: "5"
                        )
                    ],
                    limit: 25,
                    sortBy: "playCount",
                    sortAscending: false // Descending - highest play count first
                ),
                isUserEditable: false
            ),
            
            // Top 25 Recently Played - already correct
            Playlist(
                name: DefaultPlaylists.recentlyPlayed,
                criteria: SmartPlaylistCriteria(
                    rules: [
                        SmartPlaylistCriteria.Rule(
                            field: "lastPlayedDate",
                            condition: .greaterThan,
                            value: "7days"
                        )
                    ],
                    limit: 25,
                    sortBy: "lastPlayedDate",
                    sortAscending: false // Descending - most recent first
                ),
                isUserEditable: false
            )
        ]
    }
}

// Extension for Equatable & Hashable Conformance
extension Playlist: Equatable, Hashable {
    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        // Compare by ID since it's unique
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        // Hash by ID since it's unique
        hasher.combine(id)
    }
}

extension Playlist {
    mutating func loadTracks(from db: Database) throws {
        guard type == .regular else { return }
        
        // Get playlist tracks in order
        let playlistTracks = try PlaylistTrack
            .filter(PlaylistTrack.Columns.playlistId == id.uuidString)
            .order(PlaylistTrack.Columns.position)
            .fetchAll(db)
        
        // Get all track IDs
        let trackIds = playlistTracks.map { $0.trackId }
        
        // Fetch all tracks at once
        let tracksByID: [Int64: Track] = try Track
            .filter(trackIds.contains(Track.Columns.trackId))
            .fetchAll(db)
            .reduce(into: [:]) { dict, track in
                if let id = track.trackId {
                    dict[id] = track
                }
            }
        
        // Reassemble in order
        self.tracks = playlistTracks.compactMap { tracksByID[$0.trackId] }
    }
}
