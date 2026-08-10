import AppKit
import Foundation
import GRDB

/// Keyed by row id *and* artwork version, so an edited image refreshes. Rows re-render on
/// every playback publish, and decoding the JPEG each pass is visible as steady CPU use.
enum StationArtworkCache {
    /// Row thumbnails only; the full image is read from `artworkData` where shown large.
    private static let pixelSize = Int(ViewDefaults.listArtworkSize * 2)

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func image(for station: RadioStation) -> NSImage? {
        guard let data = station.artworkData, !data.isEmpty else { return nil }

        let key = "\(station.id ?? 0)-\(station.artworkVersion)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        guard let resized = context.makeImage() else { return nil }

        let thumbnail = NSImage(cgImage: resized, size: NSSize(width: pixelSize, height: pixelSize))
        cache.setObject(thumbnail, forKey: key, cost: pixelSize * pixelSize * 4)
        return thumbnail
    }
}

/// An internet radio station. Not a `Track`: streams have no duration, can't be
/// favorited and never enter the play queue. `MutablePersistableRecord` rather than
/// `PersistableRecord` because the auto-incremented id only exists after the insert.
struct RadioStation: Identifiable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?

    // User-editable
    var name: String
    var streamURL: String
    var description: String?
    var artworkData: Data?

    // Provenance and descriptive metadata, mostly from radio-browser
    var stationUUID: String?
    var faviconURL: String?
    var homepageURL: String?
    var tags: String?
    var country: String?
    var countryCode: String?
    var language: String?
    var codec: String?
    var bitrate: Int?
    var votes: Int?

    // Play statistics
    var playCount: Int = 0
    var lastPlayed: Date?
    var dateAdded: Date?
    var dateModified: Date?

    init(name: String, streamURL: String) {
        self.name = name
        self.streamURL = streamURL
    }

    var playableURL: URL? {
        InternetRadioManager.validate(streamURL: streamURL)
    }

    var artworkImage: NSImage? {
        StationArtworkCache.image(for: self)
    }

    /// `TableColumn(value:)` needs a non-optional `Comparable`.
    var sortableDateAdded: Date {
        dateAdded ?? .distantPast
    }

    /// Never-played sorts as oldest, so a descending sort leads with the most recent.
    var sortableLastPlayed: Date {
        lastPlayed ?? .distantPast
    }

    /// Every write stamps `date_modified`, so this changes for any artwork replacement -
    /// including one whose bytes happen to be the same length as the old image.
    var artworkVersion: Int64 {
        Int64((dateModified ?? .distantPast).timeIntervalSince1970 * 1000)
    }

    /// Stable UUID derived from the row id, for the UUID-keyed artwork colour caches.
    /// The whole artwork version is folded in: truncating it made the identity repeat every
    /// 65 seconds for one station, so two edits that far apart could reuse stale colours.
    var artworkCacheID: UUID {
        let string = String(format: "00000000-0000-%04X-%04X-%012d",
                            UInt16(truncatingIfNeeded: artworkVersion >> 16),
                            UInt16(truncatingIfNeeded: artworkVersion),
                            id ?? 0)
        return UUID(uuidString: string) ?? UUID()
    }

    // MARK: - GRDB Configuration

    static let databaseTableName = "internet_radio"

    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let streamURL = Column("stream_url")
        static let description = Column("description")
        static let artworkData = Column("artwork_data")
        static let stationUUID = Column("station_uuid")
        static let faviconURL = Column("favicon_url")
        static let homepageURL = Column("homepage_url")
        static let tags = Column("tags")
        static let country = Column("country")
        static let countryCode = Column("country_code")
        static let language = Column("language")
        static let codec = Column("codec")
        static let bitrate = Column("bitrate")
        static let votes = Column("votes")
        static let playCount = Column("play_count")
        static let lastPlayed = Column("last_played")
        static let dateAdded = Column("date_added")
        static let dateModified = Column("date_modified")
    }

    init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name]
        streamURL = row[Columns.streamURL]
        description = row[Columns.description]
        artworkData = row[Columns.artworkData]
        stationUUID = row[Columns.stationUUID]
        faviconURL = row[Columns.faviconURL]
        homepageURL = row[Columns.homepageURL]
        tags = row[Columns.tags]
        country = row[Columns.country]
        countryCode = row[Columns.countryCode]
        language = row[Columns.language]
        codec = row[Columns.codec]
        bitrate = row[Columns.bitrate]
        votes = row[Columns.votes]
        playCount = row[Columns.playCount] ?? 0
        lastPlayed = row[Columns.lastPlayed]
        dateAdded = row[Columns.dateAdded]
        dateModified = row[Columns.dateModified]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.name] = name
        container[Columns.streamURL] = streamURL
        container[Columns.description] = description
        container[Columns.artworkData] = artworkData
        container[Columns.stationUUID] = stationUUID
        container[Columns.faviconURL] = faviconURL
        container[Columns.homepageURL] = homepageURL
        container[Columns.tags] = tags
        container[Columns.country] = country
        container[Columns.countryCode] = countryCode
        container[Columns.language] = language
        container[Columns.codec] = codec
        container[Columns.bitrate] = bitrate
        container[Columns.votes] = votes
        container[Columns.playCount] = playCount
        container[Columns.lastPlayed] = lastPlayed
        container[Columns.dateAdded] = dateAdded ?? Date()
        container[Columns.dateModified] = Date()
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension RadioStation: Equatable {
    static func == (lhs: RadioStation, rhs: RadioStation) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.streamURL == rhs.streamURL
            && lhs.description == rhs.description
            && lhs.playCount == rhs.playCount
            && lhs.lastPlayed == rhs.lastPlayed
            && lhs.artworkVersion == rhs.artworkVersion
            && (lhs.artworkData != nil) == (rhs.artworkData != nil)
    }
}

/// A station's membership in a collection. Written but never fetched as a record, so it
/// declares no `init(row:)`; naming the columns is what keeps the collection queries in
/// the query interface instead of raw SQL.
struct PlaylistStation: TableRecord, PersistableRecord {
    var playlistId: String
    var stationId: Int64
    var position: Int
    var dateAdded: Date

    static let databaseTableName = "playlist_stations"

    enum Columns {
        static let playlistId = Column("playlist_id")
        static let stationId = Column("station_id")
        static let position = Column("position")
        static let dateAdded = Column("date_added")
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.playlistId] = playlistId
        container[Columns.stationId] = stationId
        container[Columns.position] = position
        container[Columns.dateAdded] = dateAdded
    }
}

// MARK: - Sorting

/// Separate from `TrackSortField` because stations share none of the track columns.
/// One case per `StationTableView` column: a sort the table can't show is a sort the user
/// can't check, which is why bitrate and country aren't here.
enum StationSortField: String, CaseIterable {
    case name
    case dateAdded
    case playCount
    case lastPlayed

    var displayName: String {
        switch self {
        case .name:       return String(localized: "Name")
        case .dateAdded:  return String(localized: "Date added")
        case .playCount:  return String(localized: "Play count")
        case .lastPlayed: return String(localized: "Last played")
        }
    }

    /// Must stay identical to the matching `TableColumn`'s comparator, or a sort chosen in
    /// the dropdown leaves the column header unmarked.
    func comparator(ascending: Bool) -> KeyPathComparator<RadioStation> {
        let order: SortOrder = ascending ? .forward : .reverse
        switch self {
        case .name:
            return KeyPathComparator(\RadioStation.name, comparator: String.StandardComparator.localizedStandard, order: order)
        case .dateAdded:
            return KeyPathComparator(\RadioStation.sortableDateAdded, order: order)
        case .playCount:
            return KeyPathComparator(\RadioStation.playCount, order: order)
        case .lastPlayed:
            return KeyPathComparator(\RadioStation.sortableLastPlayed, order: order)
        }
    }

    static func from(_ comparator: KeyPathComparator<RadioStation>) -> StationSortField? {
        allCases.first { $0.comparator(ascending: true).keyPath == comparator.keyPath }
    }
}
