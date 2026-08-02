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
}

extension Entity {
    // Default: no localization. Concrete types that map to a LibraryFilterType
    // override this to translate the "Unknown X" sentinel.
    var displayName: String { name }

    /// Identity for artwork caching and `.task(id:)` invalidation. The byte count is a fine
    /// stamp for a stored snapshot; types whose artwork is lazily materialised override it.
    var artworkIdentity: String { "\(id.uuidString)-\(artworkData?.count ?? 0)" }

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

// MARK: - Shared Color Defaults

extension Entity {
    var dominantColors: [NSColor] {
        guard let original = artworkData else { return [] }
        return ImageUtils.cachedDominantColors(id: id, imageData: original)
    }

    func backgroundGradientColors(isDark: Bool) -> [Color] {
        guard let original = artworkData else { return [] }
        return ImageUtils.cachedBackgroundGradientColors(id: id, imageData: original, isDark: isDark)
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
    let artworkData: Data?
    let filterType: LibraryFilterType

    var displayName: String { filterType.localizedDisplay(name) }

    var subtitle: String? {
        String(localized: "\(trackCount) songs")
    }

    init(name: String, trackCount: Int, filterType: LibraryFilterType) {
        self.id = UUID(name: "\(filterType.rawValue)-\(name)".lowercased(), namespace: EntityNamespaces.category)
        self.name = name
        self.trackCount = trackCount
        self.filterType = filterType
        self.artworkData = ImageUtils.cachedCategoryArtwork(
            text: name,
            seed: Self.artworkSeed(name: name, filterType: filterType)
        )
    }

    static func artworkSeed(name: String, filterType: LibraryFilterType) -> String {
        "\(filterType.rawValue)-\(name)"
    }

    /// `init` otherwise does its CoreText render inline on the main actor. Calling this
    /// off-main first turns that into a cache hit. Safe from any thread.
    static func warmArtwork(name: String, filterType: LibraryFilterType) {
        _ = ImageUtils.cachedCategoryArtwork(
            text: name,
            seed: artworkSeed(name: name, filterType: filterType)
        )
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

    /// Signature and byte count: a collage renders after the tile is on screen, filling
    /// artwork in without changing membership, so the signature alone never re-fires.
    var artworkIdentity: String { "\(id.uuidString)-\(signature)-\(artworkData?.count ?? 0)" }

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
    let artworkData: Data?

    var subtitle: String? {
        String(localized: "\(trackCount) songs")
    }

    init(path: String, name: String, trackCount: Int) {
        self.id = UUID(name: "folder-\(path)".lowercased(), namespace: EntityNamespaces.category)
        self.name = name
        self.path = path
        self.trackCount = trackCount
        // Seed by path so same-named folders get distinct artwork.
        self.artworkData = ImageUtils.cachedCategoryArtwork(text: name, seed: "folder-\(path)")
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
