import Foundation

// MARK: - Track Metadata

struct TrackMetadata {
    let url: URL
    var title: String?
    var artist: String?
    var album: String?
    var composer: String?
    var genre: String?
    var year: String?
    var duration: Double = 0
    var artworkData: Data?
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
    var lossless: Bool?

    var sortTitle: String?
    var sortArtist: String?
    var sortAlbum: String?
    var sortAlbumArtist: String?

    var extended: ExtendedMetadata

    init(url: URL) {
        self.url = url
        self.extended = ExtendedMetadata()
    }
}

// MARK: - Artwork Compression Cache

/// Thread-safe cache for compressed artwork data within a processing chunk.
/// Avoids re-compressing identical album artwork across tracks in the same batch.
/// Keyed by full bytes, not `hashValue` (`Data` hashes only a prefix, so covers can collide).
actor ArtworkCompressionCache {
    private var cache: [Data: Data] = [:]

    func get(for data: Data) -> Data? {
        cache[data]
    }

    func store(original: Data, compressed: Data) {
        cache[original] = compressed
    }
}

// MARK: - Metadata Reader

/// Backend-agnostic contract for reading a file's tags, audio properties, and
/// artwork into a `TrackMetadata`. Concrete readers live in their own files and
/// hold only engine-specific code.
protocol MetadataReader {
    func extractMetadata(
        from url: URL,
        externalArtwork: Data?,
        artworkCache: ArtworkCompressionCache?
    ) async -> TrackMetadata
}

// MARK: - Metadata Engine

enum MetadataEngine {
    /// Extract metadata from an audio file using the selected backend's reader.
    /// - Parameters:
    ///   - url: The URL of the audio file
    ///   - externalArtwork: Optional external artwork to use if file has none
    ///   - artworkCache: Optional shared cache to avoid re-compressing identical artwork
    /// - Returns: TrackMetadata containing all extracted information
    static func extractMetadata(
        from url: URL,
        externalArtwork: Data? = nil,
        artworkCache: ArtworkCompressionCache? = nil
    ) async -> TrackMetadata {
        await reader().extractMetadata(
            from: url,
            externalArtwork: externalArtwork,
            artworkCache: artworkCache
        )
    }

    /// Builds the reader for the selected backend.
    private static func reader() -> MetadataReader {
        switch MediaBackend.current {
        case .sfb:
            return SFBMetadataReader()
        case .crescendo:
            return CrescendoMetadataReader()
        }
    }
}
