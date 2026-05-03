import Foundation
import AppKit
import SwiftUI
import CryptoKit

// MARK: - Artist Initials

extension String {
    var artistInitials: String {
        let words = split(separator: " ")
        if words.count >= 2 {
            return "\(words.first!.prefix(1))\(words.last!.prefix(1))".uppercased()
        }
        return String(prefix(1)).uppercased()
    }
}

// MARK: - Entity Protocol
protocol Entity: Identifiable {
    var id: UUID { get }
    var name: String { get }
    var subtitle: String? { get }
    var trackCount: Int { get }
    var artworkData: Data? { get }
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

    var subtitle: String? {
        "\(trackCount) \(trackCount == 1 ? "song" : "songs")"
    }

    init(name: String, tracks: [Track]) {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        self.id = UUID(name: name.lowercased(), namespace: namespace)
        self.name = name
        self.tracks = tracks
        self.trackCount = tracks.count

        let trackWithArt = tracks.first { $0.albumArtworkData != nil }
        self.artworkData = trackWithArt?.albumArtworkData
    }

    init(name: String, trackCount: Int, artworkData: Data? = nil) {
        let namespace = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        self.id = UUID(name: name.lowercased(), namespace: namespace)
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

    var subtitle: String? {
        year
    }

    init(name: String, tracks: [Track]) {
        let namespace = UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8")!
        self.id = UUID(name: name.lowercased(), namespace: namespace)
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
            let namespace = UUID(uuidString: "6BA7B811-9DAD-11D1-80B4-00C04FD430C8")!
            self.id = UUID(name: name.lowercased(), namespace: namespace)
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
    private static var generatedArtworkCache = NSCache<NSString, NSData>()

    var subtitle: String? {
        "\(trackCount) \(trackCount == 1 ? "song" : "songs")"
    }

    init(name: String, trackCount: Int, filterType: LibraryFilterType) {
        let namespace = UUID(uuidString: "6BA7B812-9DAD-11D1-80B4-00C04FD430C8")!
        self.id = UUID(name: "\(filterType.rawValue)-\(name)".lowercased(), namespace: namespace)
        self.name = name
        self.trackCount = trackCount
        self.filterType = filterType

        let cacheKey = "\(filterType.rawValue)-\(name)" as NSString
        if let cached = CategoryEntity.generatedArtworkCache.object(forKey: cacheKey) {
            self.artworkData = cached as Data
        } else {
            let generated = ImageUtils.generateCategoryArtwork(text: name, seed: "\(filterType.rawValue)-\(name)")
            if let generated {
                CategoryEntity.generatedArtworkCache.setObject(generated as NSData, forKey: cacheKey)
            }
            self.artworkData = generated
        }
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
