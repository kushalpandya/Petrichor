import Foundation
import GRDB

class Album: Identifiable, ObservableObject, FetchableRecord, PersistableRecord {
    var id: Int64?
    let title: String
    let normalizedTitle: String
    var sortTitle: String?
    var artworkData: Data?

    // Album metadata
    @Published var releaseDate: String?
    var releaseYear: Int?
    var albumType: String? // 'album', 'single', 'ep', 'compilation'
    var totalTracks: Int?
    var totalDiscs: Int?

    // External API metadata
    var description: String?
    var review: String?
    var reviewSource: String?
    var coverArtUrl: String?
    var thumbnailUrl: String?

    // External identifiers
    var discogsId: String?
    var musicbrainzId: String?
    var spotifyId: String?
    var appleMusicId: String?

    // Additional metadata
    var label: String?
    var catalogNumber: String?
    var barcode: String?
    var genres: [String]?

    // Timestamps
    var createdAt: Date?
    var updatedAt: Date?

    // Transient properties
    @Published var trackCount: Int = 0

    // MARK: - Initialization

    init(title: String) {
        self.title = title
        self.normalizedTitle = Album.normalizeTitle(title)
        self.sortTitle = title
    }

    /// Normalizes an album title for deduplication and matching.
    static func normalizeTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: " - ", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .replacingOccurrences(of: "the ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - GRDB Configuration

    static let databaseTableName = "albums"

    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let normalizedTitle = Column("normalized_title")
        static let sortTitle = Column("sort_title")
        static let artworkData = Column("artwork_data")
        static let releaseDate = Column("release_date")
        static let releaseYear = Column("release_year")
        static let albumType = Column("album_type")
        static let totalTracks = Column("total_tracks")
        static let totalDiscs = Column("total_discs")
        static let description = Column("description")
        static let review = Column("review")
        static let reviewSource = Column("review_source")
        static let coverArtUrl = Column("cover_art_url")
        static let thumbnailUrl = Column("thumbnail_url")
        static let discogsId = Column("discogs_id")
        static let musicbrainzId = Column("musicbrainz_id")
        static let spotifyId = Column("spotify_id")
        static let appleMusicId = Column("apple_music_id")
        static let label = Column("label")
        static let catalogNumber = Column("catalog_number")
        static let barcode = Column("barcode")
        static let genres = Column("genres")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    // MARK: - FetchableRecord

    required init(row: Row) throws {
        id = row[Columns.id]
        title = row[Columns.title]
        normalizedTitle = row[Columns.normalizedTitle]
        sortTitle = row[Columns.sortTitle]
        artworkData = row[Columns.artworkData]
        releaseDate = row[Columns.releaseDate]
        releaseYear = row[Columns.releaseYear]
        albumType = row[Columns.albumType]
        totalTracks = row[Columns.totalTracks]
        totalDiscs = row[Columns.totalDiscs]
        description = row[Columns.description]
        review = row[Columns.review]
        reviewSource = row[Columns.reviewSource]
        coverArtUrl = row[Columns.coverArtUrl]
        thumbnailUrl = row[Columns.thumbnailUrl]
        discogsId = row[Columns.discogsId]
        musicbrainzId = row[Columns.musicbrainzId]
        spotifyId = row[Columns.spotifyId]
        appleMusicId = row[Columns.appleMusicId]
        label = row[Columns.label]
        catalogNumber = row[Columns.catalogNumber]
        barcode = row[Columns.barcode]

        // Decode JSON array
        if let genresJSON: String = row[Columns.genres],
           let data = genresJSON.data(using: .utf8) {
            genres = try? JSONDecoder().decode([String].self, from: data)
        }

        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.title] = title
        container[Columns.normalizedTitle] = normalizedTitle
        container[Columns.sortTitle] = sortTitle
        container[Columns.releaseDate] = releaseDate
        container[Columns.releaseYear] = releaseYear
        container[Columns.albumType] = albumType
        container[Columns.totalTracks] = totalTracks
        container[Columns.totalDiscs] = totalDiscs
        container[Columns.description] = description
        container[Columns.review] = review
        container[Columns.reviewSource] = reviewSource
        container[Columns.coverArtUrl] = coverArtUrl
        container[Columns.thumbnailUrl] = thumbnailUrl
        container[Columns.discogsId] = discogsId
        container[Columns.musicbrainzId] = musicbrainzId
        container[Columns.spotifyId] = spotifyId
        container[Columns.appleMusicId] = appleMusicId
        container[Columns.label] = label
        container[Columns.catalogNumber] = catalogNumber
        container[Columns.barcode] = barcode

        // Encode JSON array
        if let genres = genres {
            container[Columns.genres] = try? JSONEncoder().encode(genres).utf8String
        }

        container[Columns.createdAt] = createdAt ?? Date()
        container[Columns.updatedAt] = Date()
    }

    func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Associations

    static let tracks = hasMany(Track.self, using: ForeignKey(["album_id"]))
    static let albumArtists = hasMany(AlbumArtist.self)
    static let artists = hasMany(Artist.self, through: albumArtists, using: AlbumArtist.artist)

    // Helper to extract year from release date
    func extractReleaseYear() -> Int? {
        guard let releaseDate = releaseDate else { return nil }

        // Try to parse year from common date formats
        let yearPatterns = [
            "^(\\d{4})",           // YYYY at start
            "(\\d{4})$",           // YYYY at end
            "(\\d{4})-\\d{2}-\\d{2}" // YYYY-MM-DD
        ]

        for pattern in yearPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: releaseDate, range: NSRange(releaseDate.startIndex..., in: releaseDate)),
               let yearRange = Range(match.range(at: 1), in: releaseDate) {
                return Int(releaseDate[yearRange])
            }
        }

        return nil
    }
}

// MARK: - Equatable

extension Album: Equatable {
    static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension Album: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
