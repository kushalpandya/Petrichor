import SwiftUI

// MARK: - Sort Field Enum

enum TrackSortField: String, CaseIterable {
    case trackNumber
    case discNumber
    case favorite
    case title
    case artist
    case album
    case genre
    case year
    case composer
    case filename
    case duration
    case dateAdded
    case custom

    var displayName: String {
        switch self {
        case .trackNumber: return "Track number (#)"
        case .discNumber: return "Disc number"
        case .favorite: return "Favorite"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .genre: return "Genre"
        case .year: return "Year"
        case .composer: return "Composer"
        case .filename: return "Filename"
        case .duration: return "Duration"
        case .dateAdded: return "Date added"
        case .custom: return "Custom"
        }
    }

    func getComparator(ascending: Bool) -> KeyPathComparator<Track> {
        let sortComparators: [TrackSortField: KeyPathComparator<Track>] = [
            .trackNumber: KeyPathComparator(\Track.sortableTrackNumber, order: ascending ? .forward : .reverse),
            .discNumber: KeyPathComparator(\Track.sortableDiscNumber, order: ascending ? .forward : .reverse),
            .favorite: KeyPathComparator(\Track.sortableIsFavorite, order: ascending ? .forward : .reverse),
            .title: KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse),
            .artist: KeyPathComparator(\Track.artist, order: ascending ? .forward : .reverse),
            .album: KeyPathComparator(\Track.album, order: ascending ? .forward : .reverse),
            .genre: KeyPathComparator(\Track.genre, order: ascending ? .forward : .reverse),
            .year: KeyPathComparator(\Track.year, order: ascending ? .forward : .reverse),
            .composer: KeyPathComparator(\Track.composer, order: ascending ? .forward : .reverse),
            .filename: KeyPathComparator(\Track.filename, order: ascending ? .forward : .reverse),
            .duration: KeyPathComparator(\Track.duration, order: ascending ? .forward : .reverse),
            .dateAdded: KeyPathComparator(\Track.dateAdded, order: ascending ? .forward : .reverse),
            .custom: KeyPathComparator(\Track.sortableDateAdded, order: .forward)
        ]

        return sortComparators[self] ?? KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse)
    }

    /// Standard sort fields (excludes custom, which is playlist-only)
    static var sortFields: [TrackSortField] {
        [.trackNumber, .discNumber, .favorite, .title, .artist, .album, .genre, .year, .composer, .filename, .duration, .dateAdded]
    }

    // MARK: - Comparator Parsing

    /// Map of KeyPathComparator description substrings to sort fields.
    private static let comparatorKeyMap: [(String, TrackSortField)] = [
        ("sortableTrackNumber", .trackNumber),
        ("sortableDiscNumber", .discNumber),
        ("sortableIsFavorite", .favorite),
        ("sortableDateAdded", .dateAdded),
        ("dateAdded", .dateAdded),
        ("title", .title),
        ("artist", .artist),
        ("album", .album),
        ("genre", .genre),
        ("year", .year),
        ("composer", .composer),
        ("filename", .filename),
        ("duration", .duration),
    ]

    /// Detect the sort field from a KeyPathComparator array by parsing its description.
    static func detect(from sortOrder: [KeyPathComparator<Track>]) -> TrackSortField {
        guard let firstSort = sortOrder.first else { return .title }
        let sortString = String(describing: firstSort)
        for (key, field) in comparatorKeyMap {
            if sortString.contains(key) {
                return field
            }
        }
        return .title
    }

    /// Detect whether the sort order is ascending from a KeyPathComparator array.
    static func isAscending(from sortOrder: [KeyPathComparator<Track>]) -> Bool {
        guard let firstSort = sortOrder.first else { return true }
        return String(describing: firstSort).contains("forward")
    }

    /// The UserDefaults storage key (matches rawValue).
    var storageKey: String { rawValue }

    /// Look up a sort field from its storage key.
    static func from(storageKey: String) -> TrackSortField? {
        TrackSortField(rawValue: storageKey)
    }
}

// MARK: - TrackTableOptionsDropdown

struct TrackTableOptionsDropdown: View {
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var tableRowSize: TableRowSize
    private let playlistID: UUID?
    private let showCustomSort: Bool
    @State private var isCustomSort = false

    init(
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>,
        playlistID: UUID? = nil,
        showCustomSort: Bool = false
    ) {
        self._sortOrder = sortOrder
        self._tableRowSize = tableRowSize
        self.playlistID = playlistID
        self.showCustomSort = showCustomSort
    }

    private var currentSortField: TrackSortField {
        if isCustomSort {
            return .custom
        }
        return TrackSortField.detect(from: sortOrder)
    }

    private var isAscending: Bool {
        TrackSortField.isAscending(from: sortOrder)
    }

    var body: some View {
        Menu {
            Section("Sort by") {
                ForEach(TrackSortField.sortFields, id: \.self) { field in
                    Toggle(field.displayName, isOn: Binding(
                        get: { currentSortField == field },
                        set: { _ in setSortField(field) }
                    ))
                }

                if showCustomSort {
                    Divider()

                    Toggle(TrackSortField.custom.displayName, isOn: Binding(
                        get: { isCustomSort },
                        set: { _ in setSortField(.custom) }
                    ))
                }
            }

            Divider()

            Section("Sort order") {
                Toggle("Ascending", isOn: Binding(
                    get: { isAscending },
                    set: { _ in setSortAscending(true) }
                ))

                Toggle("Descending", isOn: Binding(
                    get: { !isAscending },
                    set: { _ in setSortAscending(false) }
                ))
            }
            .disabled(isCustomSort)

            Divider()

            Section("Row size") {
                ForEach([TableRowSize.expanded, TableRowSize.compact], id: \.self) { size in
                    Toggle(size.displayName, isOn: Binding(
                        get: { tableRowSize == size },
                        set: { _ in setRowSize(size) }
                    ))
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 14)
        .hoverEffect(activeBackgroundColor: Color(NSColor.controlColor))
        .help("Sort and display options")
        .onAppear {
            syncCustomSortState()
        }
        .onChange(of: sortOrder) {
            // When parent updates sortOrder (e.g. playlist switch), re-sync custom state
            syncCustomSortState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackTableSortChanged)) { notification in
            if notification.userInfo?["fromTable"] as? Bool == true,
               let newSortOrder = notification.userInfo?["sortOrder"] as? [KeyPathComparator<Track>] {
                sortOrder = newSortOrder
                // Table column header click overrides custom sort
                if isCustomSort {
                    isCustomSort = false
                }
            }
            if let customSort = notification.userInfo?["isCustomSort"] as? Bool {
                isCustomSort = customSort
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackTableRowSizeChanged)) { notification in
            if notification.userInfo?["fromTable"] as? Bool == true,
               let newRowSize = notification.userInfo?["rowSize"] as? TableRowSize {
                tableRowSize = newRowSize
            }
        }
    }

    // MARK: - Helper Methods

    private func syncCustomSortState() {
        if let playlistID = playlistID {
            isCustomSort = PlaylistSortManager.shared.getSortField(for: playlistID) == .custom
        } else {
            isCustomSort = false
        }
    }

    private func setSortField(_ field: TrackSortField) {
        let isCustom = field == .custom
        isCustomSort = isCustom

        if let playlistID = playlistID {
            PlaylistSortManager.shared.setSortField(field, for: playlistID)
        }

        let newComparator = field.getComparator(ascending: isAscending)
        let userDefaultsKey = playlistID != nil ? "playlistTableSortOrder" : "trackTableSortOrder"

        NotificationCenter.default.post(
            name: .trackTableSortChanged,
            object: nil,
            userInfo: [
                "sortOrder": [newComparator],
                "userDefaultsKey": userDefaultsKey,
                "isCustomSort": isCustom
            ]
        )
    }

    private func setSortAscending(_ ascending: Bool) {
        let newComparator = currentSortField.getComparator(ascending: ascending)

        let userDefaultsKey = playlistID != nil ? "playlistTableSortOrder" : "trackTableSortOrder"

        if let playlistID = playlistID {
            PlaylistSortManager.shared.setSortAscending(ascending, for: playlistID)
        }

        NotificationCenter.default.post(
            name: .trackTableSortChanged,
            object: nil,
            userInfo: [
                "sortOrder": [newComparator],
                "userDefaultsKey": userDefaultsKey,
                "isCustomSort": false
            ]
        )
    }

    private func setRowSize(_ size: TableRowSize) {
        UserDefaults.standard.set(size.rawValue, forKey: "trackTableRowSize")

        NotificationCenter.default.post(
            name: .trackTableRowSizeChanged,
            object: nil,
            userInfo: ["rowSize": size]
        )
    }
}
