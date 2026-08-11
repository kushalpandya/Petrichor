import SwiftUI

/// Every entity of one type, as pinned to Home; Artists and Albums come from the manager's caches.
struct EntityTypeView: View {
    let filterType: LibraryFilterType
    /// Transient role carrier, not a real pin: album artists and composers are `ArtistEntity` too.
    let onSelectEntity: (any Entity, PinnedItem?) -> Void

    @EnvironmentObject var libraryManager: LibraryManager

    @AppStorage("entitySortAscending")
    private var entitySortAscending: Bool = true

    @AppStorage("albumSortBy")
    private var albumSortBy: AlbumSortOption = .album

    @State private var artistEntities: [ArtistEntity] = []
    @State private var albumEntities: [AlbumEntity] = []
    @State private var categoryEntities: [CategoryEntity] = []
    @State private var isLoading = true
    @State private var refreshGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if isLoading {
                ActivityAnimation(size: .large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                NoMusicEmptyStateView(context: .localLibrary)
            } else {
                grid
            }
        }
        .task(id: "\(filterType.rawValue)-\(refreshGeneration)") {
            await load()
        }
        .onChange(of: entitySortAscending) {
            sort()
        }
        .onChange(of: albumSortBy) {
            sort()
        }
        // @Published fires on willSet, so the manager still holds the old array here.
        // `isLoading` gates the replay a new subscriber gets, which `load()` already sorted.
        .onReceive(libraryManager.$cachedArtistEntities) { artists in
            guard filterType == .artists, !isLoading else { return }
            let items = libraryManager.cachedLibraryFilterItems(for: filterType) ?? []
            artistEntities = sortedArtists(addingUnknownArtistIfNeeded(to: artists, from: items))
        }
        .onReceive(libraryManager.$cachedAlbumEntities) { albums in
            guard filterType == .albums, !isLoading else { return }
            let items = libraryManager.cachedLibraryFilterItems(for: filterType) ?? []
            albumEntities = sortedAlbums(addingUnknownAlbumIfNeeded(to: albums, from: items))
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
            refreshGeneration += 1
        }
    }

    // MARK: - Header

    private var header: some View {
        TrackListHeader(title: filterType.pluralDisplayName, trackCount: entityCount) {
            if filterType == .albums {
                albumSortMenu
            } else {
                SortDirectionButton(ascending: $entitySortAscending)
            }
        }
    }

    private var albumSortMenu: some View {
        Menu {
            Section("Sort by") {
                Toggle("Album", isOn: albumSortBinding(.album))
                Toggle("Album artist", isOn: albumSortBinding(.artist))
                Toggle("Year", isOn: albumSortBinding(.year))
                Toggle("Date added", isOn: albumSortBinding(.dateAdded))
            }

            Divider()

            Section("Sort order") {
                Toggle("Ascending", isOn: sortDirectionBinding(ascending: true))
                Toggle("Descending", isOn: sortDirectionBinding(ascending: false))
            }
        } label: {
            Image(systemName: Icons.sortMenu)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverEffect(activeBackgroundColor: Color(NSColor.controlColor))
        .help("Sort albums")
    }

    private func albumSortBinding(_ option: AlbumSortOption) -> Binding<Bool> {
        Binding(
            get: { albumSortBy == option },
            set: { _ in albumSortBy = option }
        )
    }

    private func sortDirectionBinding(ascending: Bool) -> Binding<Bool> {
        Binding(
            get: { entitySortAscending == ascending },
            set: { _ in entitySortAscending = ascending }
        )
    }

    // MARK: - Grid

    @ViewBuilder private var grid: some View {
        switch filterType {
        case .artists, .albumArtists, .composers:
            // Album artists and composers pin by filter type, not by entity:
            // `createPinContextMenuItem(for:)` maps any `ArtistEntity` to `artists`.
            EntityGridView(
                entities: artistEntities,
                onSelectEntity: { onSelectEntity($0, filterType == .artists ? nil : roleCarrier(for: $0.name)) },
                contextMenuItems: {
                    filterType == .artists
                        ? libraryManager.contextMenuItems(for: $0)
                        : libraryManager.contextMenuItems(filterType: filterType, filterValue: $0.name)
                }
            )
        case .albums:
            EntityGridView(
                entities: albumEntities,
                onSelectEntity: { onSelectEntity($0, nil) },
                contextMenuItems: { libraryManager.contextMenuItems(for: $0) }
            )
        case .genres, .decades, .years:
            EntityGridView(
                entities: categoryEntities,
                onSelectEntity: { onSelectEntity($0, nil) },
                contextMenuItems: { libraryManager.contextMenuItems(for: $0) }
            )
        }
    }

    private func roleCarrier(for name: String) -> PinnedItem {
        PinnedItem(filterType: filterType, filterValue: name, displayName: name)
    }

    private var entityCount: Int {
        switch filterType {
        case .artists, .albumArtists, .composers: return artistEntities.count
        case .albums: return albumEntities.count
        case .genres, .decades, .years: return categoryEntities.count
        }
    }

    private var isEmpty: Bool { entityCount == 0 }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        switch filterType {
        case .artists:
            await libraryManager.loadEntitiesAsync()
            let items = await libraryManager.libraryFilterItems(for: filterType)
            guard !Task.isCancelled else { return }
            artistEntities = sortedArtists(addingUnknownArtistIfNeeded(
                to: libraryManager.cachedArtistEntities,
                from: items
            ))

        case .albums:
            await libraryManager.loadEntitiesAsync()
            let items = await libraryManager.libraryFilterItems(for: filterType)
            guard !Task.isCancelled else { return }
            albumEntities = sortedAlbums(addingUnknownAlbumIfNeeded(
                to: libraryManager.cachedAlbumEntities,
                from: items
            ))

        case .albumArtists, .composers:
            let role = filterType.artistRole ?? TrackArtist.Role.artist
            let database = libraryManager.databaseManager
            let fetched = await Task.detached { database.getArtistEntities(role: role) }.value
            let items = await libraryManager.libraryFilterItems(for: filterType)
            guard !Task.isCancelled else { return }
            artistEntities = sortedArtists(addingUnknownArtistIfNeeded(to: fetched, from: items))

        case .genres, .decades, .years:
            let items = await libraryManager.libraryFilterItems(for: filterType)
            guard !Task.isCancelled else { return }
            categoryEntities = sortedCategories(
                items.map { CategoryEntity(name: $0.name, trackCount: $0.count, filterType: filterType) }
            )
        }
    }

    private func addingUnknownArtistIfNeeded(
        to entities: [ArtistEntity],
        from items: [LibraryFilterItem]
    ) -> [ArtistEntity] {
        guard let unknown = items.first(where: { $0.name == filterType.unknownPlaceholder }),
              !entities.contains(where: { $0.name == unknown.name }) else { return entities }

        return entities + [ArtistEntity(name: unknown.name, trackCount: unknown.count)]
    }

    private func addingUnknownAlbumIfNeeded(
        to entities: [AlbumEntity],
        from items: [LibraryFilterItem]
    ) -> [AlbumEntity] {
        guard let unknown = items.first(where: { $0.name == filterType.unknownPlaceholder }),
              !entities.contains(where: { $0.name == unknown.name }) else { return entities }

        return entities + [AlbumEntity(name: unknown.name, trackCount: unknown.count)]
    }

    // MARK: - Sorting

    private func sort() {
        switch filterType {
        case .artists, .albumArtists, .composers:
            artistEntities = sortedArtists(artistEntities)
        case .albums:
            albumEntities = sortedAlbums(albumEntities)
        case .genres, .decades, .years:
            categoryEntities = sortedCategories(categoryEntities)
        }
    }

    private func sortedArtists(_ artists: [ArtistEntity]) -> [ArtistEntity] {
        artists.sorted { compareNames($0.name, $1.name) }
    }

    /// Years and decades sort numerically; unknowns last, matching the Library sidebar.
    private func sortedCategories(_ categories: [CategoryEntity]) -> [CategoryEntity] {
        let unknown = filterType.unknownPlaceholder
        let known = categories.filter { $0.name != unknown }
        let unknowns = categories.filter { $0.name == unknown }

        let sorted: [CategoryEntity]
        if filterType == .years || filterType == .decades {
            sorted = known.sorted { first, second in
                let left = Int(first.name.prefix(4)) ?? 0
                let right = Int(second.name.prefix(4)) ?? 0
                if left == right { return compareNames(first.name, second.name) }
                return entitySortAscending ? left < right : left > right
            }
        } else {
            sorted = known.sorted { compareNames($0.name, $1.name) }
        }

        return sorted + unknowns
    }

    private func compareNames(_ first: String, _ second: String) -> Bool {
        let comparison = first.localizedCaseInsensitiveCompare(second)
        return entitySortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
    }

    private func sortedAlbums(_ albums: [AlbumEntity]) -> [AlbumEntity] {
        func tiebreaker(_ first: AlbumEntity, _ second: AlbumEntity) -> Bool {
            compareNames(first.name, second.name)
        }

        switch albumSortBy {
        case .album:
            return albums.sorted { compareNames($0.name, $1.name) }

        case .artist:
            return albums.sorted { first, second in
                let comparison = (first.artistName ?? "").localizedCaseInsensitiveCompare(second.artistName ?? "")
                if comparison == .orderedSame { return tiebreaker(first, second) }
                return entitySortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }

        case .year:
            return albums.sorted { first, second in
                let comparison = (first.year ?? "").compare(second.year ?? "")
                if comparison == .orderedSame { return tiebreaker(first, second) }
                return entitySortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
            }

        case .dateAdded:
            return albums.sorted { first, second in
                let left = first.dateAdded ?? .distantPast
                let right = second.dateAdded ?? .distantPast
                if left == right { return tiebreaker(first, second) }
                return entitySortAscending ? left < right : left > right
            }
        }
    }
}

#Preview {
    EntityTypeView(filterType: .genres) { _, _ in }
        .environmentObject(LibraryManager())
        .frame(width: 800, height: 600)
}
