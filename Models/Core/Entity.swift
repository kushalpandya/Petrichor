import Foundation
import AppKit
import SwiftUI

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
    init(name: String, namespace: UUID) {
        let combined = "\(namespace.uuidString)-\(name)"
        let hash = combined.hashValue
        let uuidString = String(
            format: "%08X-%04X-%04X-%04X-%012X",
            UInt32(hash & 0xFFFFFFFF),
            UInt16((hash >> 32) & 0xFFFF),
            UInt16((hash >> 48) & 0x0FFF) | 0x5000,
            UInt16((hash >> 60) & 0x3FFF) | 0x8000,
            UInt64(abs(hash)) & 0xFFFFFFFFFFFF
        )
        self = UUID(uuidString: uuidString)!
    }
}
