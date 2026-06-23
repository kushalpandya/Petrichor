import Foundation
import AppKit
import GRDB

enum PlaylistType: String, Codable {
    case regular
    case smart
}

// Smart playlist criteria
struct SmartPlaylistCriteria: Codable, Equatable {
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
        case greaterThanOrEqual
        case lessThan
        case lessThanOrEqual
    }
    
    struct Rule: Codable, Equatable {
        let field: String  // "artist", "album", "genre", "year", "playCount", etc.
        let condition: Condition
        let value: String
    }
    
    let matchType: MatchType
    let rules: [Rule]
    let limit: Int?  // Track count limit (e.g., 25 for "Top 25")
    let sortBy: String?  // "dateAdded", "lastPlayed", "playCount", etc.
    let sortAscending: Bool
    // When true, the playlist re-evaluates its rules on library changes.
    // When false, the rules run once at creation and the result is frozen as a snapshot.
    let autoUpdate: Bool

    // Default initializer
    init(
        matchType: MatchType = .all,
        rules: [Rule] = [],
        limit: Int? = nil,
        sortBy: String? = nil,
        sortAscending: Bool = true,
        autoUpdate: Bool = true
    ) {
        self.matchType = matchType
        self.rules = rules
        self.limit = limit
        self.sortBy = sortBy
        self.sortAscending = sortAscending
        self.autoUpdate = autoUpdate
    }

    private enum CodingKeys: String, CodingKey {
        case matchType, rules, limit, sortBy, sortAscending, autoUpdate
    }

    // Custom decoder keeps backward compatibility: criteria persisted before
    // `autoUpdate` existed (the built-in defaults and any user playlists) lack
    // the key, so default it to `true` rather than failing to decode.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchType = try container.decode(MatchType.self, forKey: .matchType)
        rules = try container.decode([Rule].self, forKey: .rules)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        sortBy = try container.decodeIfPresent(String.self, forKey: .sortBy)
        sortAscending = try container.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? true
        autoUpdate = try container.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
    }
}

// Cache manager for playlist artwork
private class PlaylistArtworkCache {
    static let shared = PlaylistArtworkCache()
    // Keyed on the cover-feeding tracks' stable database IDs (order-independent), so the
    // cache survives reloads (which mint new per-instance `Track.id`s) and reorders.
    private var cache: [UUID: (artwork: Data, trackIDs: [Int64])] = [:]

    func getCachedArtwork(for playlistID: UUID, currentTrackIDs: [Int64]) -> Data? {
        guard let cached = cache[playlistID] else { return nil }
        return cached.trackIDs == currentTrackIDs ? cached.artwork : nil
    }

    func setCachedArtwork(_ artwork: Data, for playlistID: UUID, trackIDs: [Int64]) {
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
    
    // Calculate total duration of the playlist
    var totalDuration: Double {
        tracks.reduce(0) { $0 + $1.duration }
    }

    var formattedTotalDuration: String {
        HelperUtils.formattedDuration(totalDuration)
    }
    
    var artworkData: Data? {
        if let customCover = coverArtworkData {
            return customCover
        }
        let selected = collageTracks()
        let selectedIDs = selected.compactMap { $0.trackId }
        return PlaylistArtworkCache.shared.getCachedArtwork(for: id, currentTrackIDs: selectedIDs)
    }

    func warmArtworkCacheIfNeeded() async -> Data? {
        if let customCover = coverArtworkData {
            return customCover
        }
        let selected = collageTracks()
        let selectedIDs = selected.compactMap { $0.trackId }
        if let cached = PlaylistArtworkCache.shared.getCachedArtwork(for: id, currentTrackIDs: selectedIDs) {
            return cached
        }
        let playlistID = id
        let collage = await Task.detached(priority: .utility) {
            Self.renderCollageArtwork(from: selected)
        }.value
        if let collage {
            PlaylistArtworkCache.shared.setCachedArtwork(collage, for: playlistID, trackIDs: selectedIDs)
        }
        return collage
    }

    /// Stable, order-independent signature of the playlist's track membership. Used as the
    /// view's artwork task id so the collage work only re-fires when the *set* of tracks
    /// changes, not when the playlist is merely reordered. Kept cheap (no sort/allocation)
    /// since it's evaluated on every `body` pass; the cache check inside
    /// `warmArtworkCacheIfNeeded` still skips the actual render when the cover is unchanged.
    var artworkSignature: String {
        if coverArtworkData != nil {
            return "\(id)-custom"
        }
        var digest: Int64 = 0
        for track in tracks {
            if let trackId = track.trackId { digest = digest &+ trackId }
        }
        return "\(id)-\(tracks.count)-\(digest)"
    }

    // Get the effective track limit for display
    var trackLimit: Int? {
        smartCriteria?.limit
    }

    /// Returns up to 4 tracks with artwork, preferring unique albums. Selection is
    /// order-independent (candidates are taken in stable `trackId` order) so the cover is a
    /// function of the playlist's *contents*, not its current sort/manual order.
    private func collageTracks() -> [Track] {
        let candidates = tracks
            .filter { $0.artworkData != nil }
            .sorted { ($0.trackId ?? .max) < ($1.trackId ?? .max) }

        var seenAlbumIds = Set<Int64>()
        var result: [Track] = []
        for track in candidates {
            guard let albumId = track.albumId, !seenAlbumIds.contains(albumId) else { continue }
            seenAlbumIds.insert(albumId)
            result.append(track)
            if result.count == 4 { return result }
        }
        if result.count < 4 {
            for track in candidates where !result.contains(where: { $0.id == track.id }) {
                result.append(track)
                if result.count == 4 { break }
            }
        }
        return result
    }

    fileprivate static func renderCollageArtwork(from collageTracks: [Track]) -> Data? {
        guard !collageTracks.isEmpty else { return nil }

        let pixelSize = 256
        let size = CGFloat(pixelSize)

        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            Logger.warning("Failed to create CGContext for collage")
            return nil
        }

        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))

        let count = collageTracks.count

        if count == 1 {
            if let data = collageTracks[0].artworkData,
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            }
        } else {
            let positions = [(0, 0), (1, 0), (0, 1), (1, 1)]
            for (index, (col, row)) in positions.enumerated() {
                let trackIndex = count == 2 ? (index == 0 || index == 3 ? 0 : 1) : index % count

                guard let data = collageTracks[trackIndex].artworkData,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }

                context.draw(cgImage, in: CGRect(
                    x: CGFloat(col) * size / 2,
                    y: CGFloat(row) * size / 2,
                    width: size / 2,
                    height: size / 2
                ))
            }
        }

        guard let collageImage = context.makeImage() else {
            Logger.warning("Failed to create CGImage from collage context")
            return nil
        }

        // Software HEVC encode deadlocks under concurrent invocation on Intel (issue #265),
        // so mirror the JPEG fallback used by ImageUtils.compressImage.
        #if arch(x86_64)
        return ImageUtils.encodeJPEG(collageImage)
        #else
        return ImageUtils.encodeHEIC(collageImage)
        #endif
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
                    sortBy: "dateAdded",
                    sortAscending: true
                ),
                isUserEditable: false
            ),
            
            // Top 25 Most Played - tracks played 5 or more times
            Playlist(
                name: DefaultPlaylists.mostPlayed,
                criteria: SmartPlaylistCriteria(
                    rules: [
                        SmartPlaylistCriteria.Rule(
                            field: "playCount",
                            condition: .greaterThanOrEqual,
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
