import Foundation
import AppKit
import SwiftUI
import CryptoKit

// MARK: - Artist Initials

extension String {
    var artistInitials: String {
        let words = split(separator: " ")
        if words.count >= 2,
           let first = words.first,
           let last = words.last {
            return "\(first.prefix(1))\(last.prefix(1))".uppercased()
        }
        return String(prefix(1)).uppercased()
    }
}

private enum EntityNamespaces {
    static let artist = makeNamespace("6BA7B810-9DAD-11D1-80B4-00C04FD430C8")
    static let album = makeNamespace("6BA7B811-9DAD-11D1-80B4-00C04FD430C8")
    static let category = makeNamespace("6BA7B812-9DAD-11D1-80B4-00C04FD430C8")

    private static func makeNamespace(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Invalid entity namespace UUID")
        }
        return uuid
    }
}

extension Data {
    /// Stable content identity for artwork caches. Byte count alone collides for replacements.
    var artworkFingerprint: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Entity Protocol
protocol Entity: Identifiable {
    var id: UUID { get }
    var name: String { get }
    /// Display-only name; localizes the stored English "Unknown X" sentinel.
    /// `name` stays raw for identity/sorting.
    var displayName: String { get }
    var subtitle: String? { get }
    var trackCount: Int { get }
    var artworkData: Data? { get }

    // Requirements, not extension-only: extension members static-dispatch through `any Entity`.
    var artworkIdentity: String { get }
    func resolvedArtworkData(isDark: Bool) async -> Data?
    func cachedArtworkData(isDark: Bool) -> Data?
}

extension Entity {
    // Default: no localization. Concrete types that map to a LibraryFilterType
    // override this to translate the "Unknown X" sentinel.
    var displayName: String { name }

    /// Identity for artwork caching and `.task(id:)` invalidation.
    var artworkIdentity: String { "\(id.uuidString)-\(artworkData?.artworkFingerprint ?? "none")" }

    /// Artwork resolved off the main actor; procedural types render here, not in their init.
    func resolvedArtworkData(isDark: Bool) async -> Data? { artworkData }

    /// Cache-only artwork for a first render, so the detail view doesn't flash a placeholder.
    func cachedArtworkData(isDark: Bool) -> Data? { artworkData }

    /// Second line of a carousel tile, so a mixed row reads unambiguously.
    var kindLabel: String {
        if self is ArtistEntity { return String(localized: "Artist") }
        if self is AlbumEntity { return String(localized: "Album") }
        if let category = self as? CategoryEntity { return category.filterType.singularDisplayName }
        if self is PlaylistEntity { return String(localized: "Playlist") }
        if self is FolderEntity { return String(localized: "Folder") }
        return ""
    }
}

// MARK: - Artist Entity
struct ArtistEntity: Entity {
    let id: UUID
    let name: String
    let tracks: [Track]
    let trackCount: Int
    let artworkData: Data?

    var displayName: String { LibraryFilterType.artists.localizedDisplay(name) }

    var subtitle: String? {
        String(localized: "\(trackCount) songs")
    }

    init(name: String, tracks: [Track]) {
        self.id = UUID(name: name.lowercased(), namespace: EntityNamespaces.artist)
        self.name = name
        self.tracks = tracks
        self.trackCount = tracks.count

        let trackWithArt = tracks.first { $0.albumArtworkData != nil }
        self.artworkData = trackWithArt?.albumArtworkData
    }

    init(name: String, trackCount: Int, artworkData: Data? = nil) {
        self.id = UUID(name: name.lowercased(), namespace: EntityNamespaces.artist)
        self.name = name
        self.tracks = []
        self.trackCount = trackCount
        self.artworkData = artworkData
    }
}

// MARK: - Album Entity
struct AlbumEntity: Entity {
    let id: UUID
    let name: String
    let tracks: [Track]
    let trackCount: Int
    let artworkData: Data?
    let albumId: Int64?
    let year: String?
    let duration: Double?
    let artistName: String?
    let dateAdded: Date?

    var displayName: String { LibraryFilterType.albums.localizedDisplay(name) }

    var subtitle: String? {
        year
    }

    init(name: String, tracks: [Track]) {
        self.id = UUID(name: name.lowercased(), namespace: EntityNamespaces.album)
        self.name = name
        self.tracks = tracks
        self.trackCount = tracks.count
        self.albumId = nil
        self.year = nil
        self.duration = nil
        self.artistName = nil
        self.dateAdded = nil

        let trackWithArt = tracks.first { $0.albumArtworkData != nil }
        self.artworkData = trackWithArt?.albumArtworkData
    }

    init(
        name: String,
        trackCount: Int,
        artworkData: Data? = nil,
        albumId: Int64? = nil,
        year: String? = nil,
        duration: Double? = nil,
        artistName: String? = nil,
        dateAdded: Date? = nil
    ) {
        if let albumId = albumId {
            let uuidString = String(format: "00000000-0000-0000-0000-%012d", albumId)
            self.id = UUID(uuidString: uuidString) ?? UUID()
        } else {
            self.id = UUID(name: name.lowercased(), namespace: EntityNamespaces.album)
        }
        self.name = name
        self.tracks = []
        self.trackCount = trackCount
        self.artworkData = artworkData
        self.albumId = albumId
        self.year = year
        self.duration = duration
        self.artistName = artistName
        self.dateAdded = dateAdded
    }
}

// MARK: - Category Entity
struct CategoryEntity: Entity {
    let id: UUID
    let name: String
    let trackCount: Int
    let filterType: LibraryFilterType

    var displayName: String { filterType.localizedDisplay(name) }

    var subtitle: String? {
        String(localized: "\(trackCount) songs")
    }

    /// Always nil; `resolvedArtworkData` draws it off-main so building a grid costs nothing.
    var artworkData: Data? { nil }

    /// Seed-derived, so it is stable before and after the artwork renders. Call sites add the
    /// colour scheme, which the entity has no way to know.
    var artworkIdentity: String { "\(id.uuidString)-generated" }

    init(name: String, trackCount: Int, filterType: LibraryFilterType) {
        self.id = UUID(name: "\(filterType.rawValue)-\(name)".lowercased(), namespace: EntityNamespaces.category)
        self.name = name
        self.trackCount = trackCount
        self.filterType = filterType
    }

    private var artworkSeed: String { "\(filterType.rawValue)-\(name)" }

    private var artworkStyle: CategoryArtworkStyle {
        switch filterType {
        case .decades: return .decade
        case .years: return .year
        default: return .genre
        }
    }

    /// No corner label for the unknown placeholder: it wouldn't fit, and the grid labels it.
    private var artworkLabel: String? {
        name == filterType.unknownPlaceholder ? nil : name
    }

    func resolvedArtworkData(isDark: Bool) async -> Data? {
        await ImageUtils.proceduralArtwork(seed: artworkSeed, style: artworkStyle, isDark: isDark, label: artworkLabel)
    }

    func cachedArtworkData(isDark: Bool) -> Data? {
        ImageUtils.generatedCategoryArtwork(seed: artworkSeed, style: artworkStyle, isDark: isDark)
    }
}

// MARK: - Playlist Entity

/// Adapter letting a `Playlist` appear in `Entity`-generic UI. Not a conformance on
/// `Playlist`: its `artworkData` is a lazily-warmed lookup returning nil until
/// `warmArtworkCacheIfNeeded()` runs, so the byte-count identity would be wrong.
struct PlaylistEntity: Entity {
    let id: UUID
    let name: String
    let trackCount: Int
    let artworkData: Data?
    private let signature: String

    var subtitle: String? {
        String(localized: "\(trackCount) songs")
    }

    /// Signature and content identity: a collage renders after the tile is on screen, filling
    /// artwork in without changing membership, so the signature alone never re-fires.
    var artworkIdentity: String { "\(id.uuidString)-\(signature)-\(artworkData?.artworkFingerprint ?? "none")" }

    /// `trackCount` overrides `playlist.trackCount`, which is stale (often zero) for a
    /// cold smart playlist whose criteria haven't been evaluated this session.
    init(playlist: Playlist, artworkData: Data?, trackCount: Int? = nil) {
        // Safe: every other Entity id is a name-namespaced v5 UUID or the album form.
        self.id = playlist.id
        self.name = DefaultPlaylists.displayName(for: playlist)
        self.trackCount = trackCount ?? playlist.trackCount
        self.artworkData = artworkData
        self.signature = playlist.artworkSignature
    }
}

// MARK: - Folder Entity
struct FolderEntity: Entity {
    let id: UUID
    let name: String
    let path: String
    let trackCount: Int

    var subtitle: String? {
        String(localized: "\(trackCount) songs")
    }

    /// Drawn on demand, like `CategoryEntity`.
    var artworkData: Data? { nil }

    var artworkIdentity: String { "\(id.uuidString)-generated" }

    init(path: String, name: String, trackCount: Int) {
        self.id = UUID(name: "folder-\(path)".lowercased(), namespace: EntityNamespaces.category)
        self.name = name
        self.path = path
        self.trackCount = trackCount
    }

    /// Seeded by path, so same-named folders get distinct artwork.
    private var artworkSeed: String { "folder-\(path)" }

    func resolvedArtworkData(isDark: Bool) async -> Data? {
        await ImageUtils.proceduralArtwork(seed: artworkSeed, style: .folder, isDark: isDark)
    }

    func cachedArtworkData(isDark: Bool) -> Data? {
        ImageUtils.generatedCategoryArtwork(seed: artworkSeed, style: .folder, isDark: isDark)
    }
}

// MARK: - UUID Extension

extension UUID {
    /// Deterministic name-based UUID
    init(name: String, namespace: UUID) {
        var input = Data()
        withUnsafeBytes(of: namespace.uuid) { input.append(contentsOf: $0) }
        input.append(contentsOf: name.utf8)

        var digest = Array(Insecure.SHA1.hash(data: input))
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80

        let bytes: uuid_t = (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        )
        self.init(uuid: bytes)
    }
}
