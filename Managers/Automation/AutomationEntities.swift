//
// Automation App Intents - Entities & lookups
//
// The AppEntity / AppEnum types the App Intents surface exposes, plus the
// EntityQuery types that feed Shortcuts/Spotlight pickers and resolve spoken or
// typed names (EntityStringQuery) for Siri. These are independent SDK types, so
// they keep plain `Automation*` names rather than the `AM*` facade-extension
// prefix. All reads go through AutomationManager / AppCoordinator on the main
// actor.
//

import AppIntents
import Foundation

// MARK: - Library lookups

enum AutomationLibrary {
    /// Distinct values for a category (artist/genre/decade/...), excluding the "All" row.
    @MainActor
    static func values(for filterType: LibraryFilterType) -> [String] {
        guard let library = AppCoordinator.shared?.libraryManager else { return [] }
        return library.getLibraryFilterItems(for: filterType)
            .filter { !$0.isAllItem }
            .map(\.name)
    }

    /// Loose name match for spoken/typed resolution. Empty query returns everything
    /// so Shortcuts can still present the full picker.
    @MainActor
    static func match(_ string: String, in filterType: LibraryFilterType) -> [String] {
        let query = normalize(string)
        let all = values(for: filterType)
        guard !query.isEmpty else { return all }
        return all.filter { normalize($0).contains(query) }
    }

    /// ArtistParser-style normalization: lowercased, diacritics folded, a leading
    /// "the " dropped, surrounding whitespace trimmed.
    static func normalize(_ value: String) -> String {
        var result = value.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("the ") { result.removeFirst(4) }
        return result
    }

    /// Loose name filter over an entity list, applied before any mapping so we don't
    /// allocate AppEntities for non-matches. Empty query returns everything so the
    /// full picker still shows.
    static func filterByName<T>(_ items: [T], matching string: String, name: (T) -> String) -> [T] {
        let query = normalize(string)
        guard !query.isEmpty else { return items }
        return items.filter { normalize(name($0)).contains(query) }
    }

    /// Albums resolved from entities (not bare titles) so `albumId` is preserved.
    @MainActor
    static func albums() -> [AlbumAppEntity] {
        albumEntities().map(AlbumAppEntity.init)
    }

    /// Raw album entities (the in-memory cache), so callers can filter by id/name
    /// before mapping to AppEntities.
    @MainActor
    static func albumEntities() -> [AlbumEntity] {
        AppCoordinator.shared?.libraryManager.albumEntities ?? []
    }

    /// Waits (bounded) until the entity caches are populated. The albumEntities cache
    /// loads ~tens of ms after launch, so an album picker / Siri album lookup fired
    /// during cold start could otherwise read an empty cache and fail to resolve.
    /// No-op once the first load has completed (the common, warm-app case).
    @MainActor
    static func awaitAlbumsReady(timeoutMs: Int = 3000) async {
        guard let library = AppCoordinator.shared?.libraryManager else { return }
        var waited = 0
        let stepMs = 50
        while !library.entitiesLoaded && waited < timeoutMs {
            try? await Task.sleep(nanoseconds: UInt64(stepMs) * 1_000_000)
            waited += stepMs
        }
        if !library.entitiesLoaded {
            Logger.warning("Automation: album entities not loaded after \(timeoutMs)ms; album picker/lookup may be empty")
        }
    }

    /// Picker suggestions for a category, mapped into its AppEntity.
    @MainActor
    static func suggestions<E>(_ filterType: LibraryFilterType, _ make: (String) -> E) -> [E] {
        values(for: filterType).map(make)
    }

    /// Spoken/typed name matches for a category, mapped into its AppEntity.
    @MainActor
    static func matches<E>(_ filterType: LibraryFilterType, _ string: String, _ make: (String) -> E) -> [E] {
        match(string, in: filterType).map(make)
    }
}

// MARK: - Now Playing

struct TrackEntity: AppEntity {
    static let currentID = "now-playing"
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Track")
    static var defaultQuery = TrackEntityQuery()

    var id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Artist")
    var artist: String

    @Property(title: "Album")
    var album: String

    @Property(title: "Duration (seconds)")
    var duration: Double

    @Property(title: "Position (seconds)")
    var position: Double

    @Property(title: "Is Playing")
    var isPlaying: Bool

    @Property(title: "Is Favorite")
    var isFavorite: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)")
    }

    init(snapshot: NowPlayingSnapshot) {
        self.id = TrackEntity.currentID
        self.title = snapshot.title
        self.artist = snapshot.artist
        self.album = snapshot.album
        self.duration = snapshot.duration
        self.position = snapshot.position
        self.isPlaying = snapshot.isPlaying
        self.isFavorite = snapshot.isFavorite
    }
}

struct TrackEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [TrackEntity] {
        guard identifiers.contains(TrackEntity.currentID),
              let snapshot = AutomationManager.shared.nowPlayingSnapshot() else { return [] }
        return [TrackEntity(snapshot: snapshot)]
    }

    @MainActor
    func suggestedEntities() async throws -> [TrackEntity] {
        AutomationManager.shared.nowPlayingSnapshot().map { [TrackEntity(snapshot: $0)] } ?? []
    }
}

// MARK: - Repeat mode

enum RepeatModeOption: String, AppEnum {
    case off
    case all
    case one

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Repeat Mode")
    static var caseDisplayRepresentations: [RepeatModeOption: DisplayRepresentation] = [
        .off: "Off",
        .all: "Repeat All",
        .one: "Repeat One"
    ]

    var repeatMode: RepeatMode {
        switch self {
        case .off: return .off
        case .all: return .all
        case .one: return .one
        }
    }
}

// MARK: - Library category entities

// One AppEntity + EntityStringQuery pair per LibraryFilterType category. App
// Intents requires concrete (non-generic) entity and query types, so the shape
// repeats; the actual lookup and normalization logic lives once in
// AutomationLibrary, leaving each query as a one-line delegation.
//
// Identity is the value name itself (e.g. the artist name), which is what
// AMContent feeds back to `getTracksBy(filterType:value:)`.

struct ArtistAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Artist")
    static var defaultQuery = ArtistAppEntityQuery()
    var id: String { name }
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ArtistAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for ids: [String]) async throws -> [ArtistAppEntity] {
        ids.map(ArtistAppEntity.init(name:))
    }

    @MainActor
    func suggestedEntities() async throws -> [ArtistAppEntity] {
        AutomationLibrary.suggestions(.artists, ArtistAppEntity.init(name:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [ArtistAppEntity] {
        AutomationLibrary.matches(.artists, string, ArtistAppEntity.init(name:))
    }
}

// Albums carry `albumId` because album titles are not unique - two different
// "Greatest Hits" must resolve to different track sets. Identity is the albumId
// when known (falling back to the title), and the artist/year subtitle lets the
// picker and Siri tell duplicate titles apart.
struct AlbumAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Album")
    static var defaultQuery = AlbumAppEntityQuery()

    let id: String
    let name: String
    let albumId: Int64?
    let subtitle: String?

    var displayRepresentation: DisplayRepresentation {
        guard let subtitle, !subtitle.isEmpty else { return DisplayRepresentation(title: "\(name)") }
        return DisplayRepresentation(title: "\(name)", subtitle: "\(subtitle)")
    }

    init(_ entity: AlbumEntity) {
        self.name = entity.name
        self.albumId = entity.albumId
        self.id = Self.id(for: entity)
        self.subtitle = entity.artistName ?? entity.year
    }

    static func id(for entity: AlbumEntity) -> String {
        entity.albumId.map(String.init) ?? "name:\(entity.name)"
    }
}

struct AlbumAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for ids: [String]) async throws -> [AlbumAppEntity] {
        await AutomationLibrary.awaitAlbumsReady()
        let wanted = Set(ids)
        return AutomationLibrary.albumEntities()
            .filter { wanted.contains(AlbumAppEntity.id(for: $0)) }
            .map(AlbumAppEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [AlbumAppEntity] {
        await AutomationLibrary.awaitAlbumsReady()
        return AutomationLibrary.albums()
    }

    @MainActor
    func entities(matching string: String) async throws -> [AlbumAppEntity] {
        await AutomationLibrary.awaitAlbumsReady()
        return AutomationLibrary.filterByName(AutomationLibrary.albumEntities(), matching: string, name: \.name)
            .map(AlbumAppEntity.init)
    }
}

struct AlbumArtistAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Album Artist")
    static var defaultQuery = AlbumArtistAppEntityQuery()
    var id: String { name }
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct AlbumArtistAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for ids: [String]) async throws -> [AlbumArtistAppEntity] {
        ids.map(AlbumArtistAppEntity.init(name:))
    }

    @MainActor
    func suggestedEntities() async throws -> [AlbumArtistAppEntity] {
        AutomationLibrary.suggestions(.albumArtists, AlbumArtistAppEntity.init(name:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [AlbumArtistAppEntity] {
        AutomationLibrary.matches(.albumArtists, string, AlbumArtistAppEntity.init(name:))
    }
}

struct ComposerAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Composer")
    static var defaultQuery = ComposerAppEntityQuery()
    var id: String { name }
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ComposerAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for ids: [String]) async throws -> [ComposerAppEntity] {
        ids.map(ComposerAppEntity.init(name:))
    }

    @MainActor
    func suggestedEntities() async throws -> [ComposerAppEntity] {
        AutomationLibrary.suggestions(.composers, ComposerAppEntity.init(name:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [ComposerAppEntity] {
        AutomationLibrary.matches(.composers, string, ComposerAppEntity.init(name:))
    }
}

struct GenreAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Genre")
    static var defaultQuery = GenreAppEntityQuery()
    var id: String { name }
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct GenreAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for ids: [String]) async throws -> [GenreAppEntity] {
        ids.map(GenreAppEntity.init(name:))
    }

    @MainActor
    func suggestedEntities() async throws -> [GenreAppEntity] {
        AutomationLibrary.suggestions(.genres, GenreAppEntity.init(name:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [GenreAppEntity] {
        AutomationLibrary.matches(.genres, string, GenreAppEntity.init(name:))
    }
}

struct DecadeAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Decade")
    static var defaultQuery = DecadeAppEntityQuery()
    var id: String { name }
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct DecadeAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for ids: [String]) async throws -> [DecadeAppEntity] {
        ids.map(DecadeAppEntity.init(name:))
    }

    @MainActor
    func suggestedEntities() async throws -> [DecadeAppEntity] {
        AutomationLibrary.suggestions(.decades, DecadeAppEntity.init(name:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [DecadeAppEntity] {
        AutomationLibrary.matches(.decades, string, DecadeAppEntity.init(name:))
    }
}

struct YearAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Year")
    static var defaultQuery = YearAppEntityQuery()
    var id: String { name }
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct YearAppEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for ids: [String]) async throws -> [YearAppEntity] {
        ids.map(YearAppEntity.init(name:))
    }

    @MainActor
    func suggestedEntities() async throws -> [YearAppEntity] {
        AutomationLibrary.suggestions(.years, YearAppEntity.init(name:))
    }

    @MainActor
    func entities(matching string: String) async throws -> [YearAppEntity] {
        AutomationLibrary.matches(.years, string, YearAppEntity.init(name:))
    }
}

// MARK: - Playlist entity

struct PlaylistAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Playlist")
    static var defaultQuery = PlaylistEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PlaylistEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [PlaylistAppEntity] {
        allPlaylists().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [PlaylistAppEntity] {
        allPlaylists()
    }

    @MainActor
    func entities(matching string: String) async throws -> [PlaylistAppEntity] {
        AutomationLibrary.filterByName(allPlaylists(), matching: string, name: \.name)
    }

    @MainActor
    private func allPlaylists() -> [PlaylistAppEntity] {
        (AppCoordinator.shared?.playlistManager.playlists ?? [])
            .map { PlaylistAppEntity(id: $0.id, name: $0.name) }
    }
}
