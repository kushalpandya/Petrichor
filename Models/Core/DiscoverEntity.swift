//
// Value types describing a Discover carousel tile, its section state, and the snapshot
// LMDiscover validates a load against. `DiscoverEntityRef` is the durable identity kept in
// the sticky caches; `DiscoverEntityRow` is what the queries return.
//

import Foundation

// MARK: - Discover Entity Types

enum DiscoverEntityKind: String, Codable, Hashable {
    case album
    case artist
    case playlist
    case decade
    case genre

    /// Round-robin fill order. Kinds with real artwork lead, drawn categories trail.
    static let carouselOrder: [DiscoverEntityKind] = [.album, .artist, .playlist, .decade, .genre]

    var filterType: LibraryFilterType? {
        switch self {
        case .album: return .albums
        case .artist: return .artists
        case .genre: return .genres
        case .decade: return .decades
        case .playlist: return nil
        }
    }
}

/// The minimum identity needed to re-resolve a tile after relaunch. `value` is the stored
/// form, English "Unknown X" sentinels included; localization happens at display time.
struct DiscoverEntityRef: Codable, Hashable {
    let kind: DiscoverEntityKind
    let value: String
    /// `.album` only; album titles are not unique.
    let albumId: Int64?
    /// `.playlist` only.
    let playlistId: UUID?
    /// `.artist` only.
    let artistId: Int64?

    /// Keyed on stable identity, not `value`, which is a display name: otherwise a rename
    /// stops a persisted ref matching its freshly-resolved twin, dropping it from the sticky
    /// rows and letting Recently Played show it a second time.
    private var identity: String {
        switch kind {
        case .album: return "album:\(albumId.map(String.init) ?? value)"
        case .artist: return "artist:\(artistId.map(String.init) ?? value)"
        case .playlist: return "playlist:\(playlistId?.uuidString ?? value)"
        case .genre, .decade: return "\(kind.rawValue):\(value)"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    static func album(id: Int64?, title: String) -> Self {
        .init(kind: .album, value: title, albumId: id, playlistId: nil, artistId: nil)
    }

    static func artist(id: Int64?, name: String) -> Self {
        .init(kind: .artist, value: name, albumId: nil, playlistId: nil, artistId: id)
    }

    static func playlist(id: UUID, name: String) -> Self {
        .init(kind: .playlist, value: name, albumId: nil, playlistId: id, artistId: nil)
    }

    static func category(kind: DiscoverEntityKind, value: String) -> Self {
        .init(kind: kind, value: value, albumId: nil, playlistId: nil, artistId: nil)
    }
}

/// Deliberately not an `Entity`: building a `CategoryEntity` runs a CoreText render and a
/// `PlaylistEntity` needs `PlaylistManager`'s live state, neither of which belongs inside a
/// `dbQueue.read`. `LMDiscover` converts these on the main actor.
struct DiscoverEntityRow {
    let ref: DiscoverEntityRef
    let trackCount: Int
    let artworkData: Data?
    /// Album only.
    let year: String?
    /// Album primary artist.
    let artistName: String?
    /// Populated only for playlists, whose candidates come from two sources and must be
    /// re-ranked together. Other kinds are ranked by their SQL ORDER BY.
    var lastPlayed: Date?
    var hotPlays: Int = 0
    var favoriteTracks: Int = 0
    var totalPlays: Int = 0

    /// Swift twin of `DatabaseManager.rotationOrder`.
    var rotationScore: Double {
        guard let lastPlayed else { return 0 }
        let daysAgo = max(0, Date().timeIntervalSince(lastPlayed) / 86400)
        return Double(hotPlays) / (1.0 + daysAgo / DiscoverSignal.rotationHalfLifeDays)
    }

    /// Swift twin of `DatabaseManager.lovedOrder`.
    var lovedScore: Int {
        totalPlays + favoriteTracks * DiscoverSignal.favoriteWeight
    }
}

/// The signals behind the Featured and Most Loved rows.
enum DiscoverSignal {
    case inRotation
    case neglected
    case mostLoved

    static let hotPlayThreshold = 2
    static let rotationHalfLifeDays = 30.0
    /// Starring is deliberate where a play is passive, so it counts for more. A taste
    /// setting, not a derived one.
    static let favoriteWeight = 10

    var sqlHaving: String {
        switch self {
        case .inRotation: return "hotTracks >= 1 AND lastPlayed IS NOT NULL"
        case .neglected: return "maxPlayCount = 0"
        // Engagement of either kind, else an untouched library fills the row with ties.
        case .mostLoved: return "(totalPlays > 0 OR favoriteTracks > 0)"
        }
    }

    /// Swift twin of `sqlHaving`, for smart playlists that can't be aggregated in SQL.
    /// Kept adjacent so the two can't drift.
    func admits(hotTracks: Int, lastPlayed: Date?, maxPlayCount: Int, favoriteTracks: Int, totalPlays: Int) -> Bool {
        switch self {
        case .inRotation: return hotTracks >= 1 && lastPlayed != nil
        case .neglected: return maxPlayCount == 0
        case .mostLoved: return totalPlays > 0 || favoriteTracks > 0
        }
    }
}

// MARK: - Section State

/// Separates "still computing" (skeleton) from "computed, nothing to show" (message).
enum DiscoverSection {
    case loading
    case loaded([any Entity])

    var entities: [any Entity] {
        if case .loaded(let entities) = self { return entities }
        return []
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Sticky Cache

/// One JSON blob rather than parallel plist arrays, which would desynchronize given the
/// heterogeneous ref shape.
struct DiscoverFeaturedCache: Codable {
    /// Bump to make every install regenerate after a selection or ref-shape change, with no
    /// database migration. v2 added `DiscoverEntityRef.artistId`.
    static let currentVersion = 2

    let version: Int
    let refs: [DiscoverEntityRef]
}

// MARK: - Detached Task Payload

struct DiscoverPayload {
    let featuredRefs: [DiscoverEntityRef]
    let featuredRows: [DiscoverEntityRow]
    let lovedRefs: [DiscoverEntityRef]
    let lovedRows: [DiscoverEntityRow]
    let recentRows: [DiscoverEntityRow]
    let tracks: [Track]
    let smartTracks: [UUID: [Track]]
    let smart: DiscoverSmartSnapshot
    let didRegenerateFeatured: Bool
    let didRegenerateLoved: Bool
    let didRegenerateTracks: Bool
    let didRunScheduled: Bool
}

/// What Discover showed before a manual refresh blanked it, carried across every attempt so
/// an abandoned refresh restores the content the user actually had.
struct DiscoverPriorContent {
    let featured: DiscoverSection
    let recent: DiscoverSection
    let tracks: [Track]
}

// MARK: - Load Validation

/// What a Discover evaluation reads that can move underneath it mid-flight.
///
/// `versions` covers frozen smart playlists too: their membership is aggregated from
/// `playlist_tracks`, so a criteria edit invalidates rows just as thoroughly. `persistence`
/// is what versions can't give, since a frozen playlist's `dateModified` is bumped
/// synchronously and its snapshot rewritten later; a reader can otherwise see the new
/// version beside the old rows, or the empty gap between the two writes.
struct DiscoverSmartSnapshot {
    let versions: [UUID: Date]
    let persistence: SmartPlaylistPersistenceToken
}

/// Two readings are interchangeable only when both are quiescent and no rewrite completed
/// between them.
struct SmartPlaylistPersistenceToken: Equatable {
    let completions: Int
    let isQuiescent: Bool
}
