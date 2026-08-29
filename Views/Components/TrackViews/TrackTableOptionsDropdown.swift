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
    case playCount
    case lastPlayedDate
    case custom

    var displayName: String {
        switch self {
        case .trackNumber:    return String(localized: "Track number (#)")
        case .discNumber:     return String(localized: "Disc number")
        case .favorite:       return String(localized: "Favorite")
        case .title:          return String(localized: "Title")
        case .artist:         return String(localized: "Artist")
        case .album:          return String(localized: "Album")
        case .genre:          return String(localized: "Genre")
        case .year:           return String(localized: "Year")
        case .composer:       return String(localized: "Composer")
        case .filename:       return String(localized: "Filename")
        case .duration:       return String(localized: "Duration")
        case .dateAdded:      return String(localized: "Date added")
        case .playCount:      return String(localized: "Play count")
        case .lastPlayedDate: return String(localized: "Last played")
        case .custom:         return String(localized: "Custom")
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
            .playCount: KeyPathComparator(\Track.playCount, order: ascending ? .forward : .reverse),
            .lastPlayedDate: KeyPathComparator(\Track.sortableLastPlayedDate, order: ascending ? .forward : .reverse),
            .custom: KeyPathComparator(\Track.sortableDateAdded, order: .forward)
        ]

        return sortComparators[self] ?? KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse)
    }

    /// User-selectable sort fields. Hidden smart-playlist sort keys like play count and
    /// last played remain supported internally, but are omitted because the table has no
    /// matching visible columns for them.
    static var sortFields: [TrackSortField] {
        [
            .trackNumber, .discNumber, .favorite, .title, .artist, .album, .genre,
            .year, .composer, .filename, .duration, .dateAdded
        ]
    }

    // MARK: - Comparator Detection

    static func detect(from sortOrder: [KeyPathComparator<Track>]) -> TrackSortField {
        guard let firstSort = sortOrder.first else { return .title }
        return comparatorMatch(for: firstSort)?.field ?? .title
    }

    static func isAscending(from sortOrder: [KeyPathComparator<Track>]) -> Bool {
        guard let firstSort = sortOrder.first else { return true }
        return comparatorMatch(for: firstSort)?.ascending ?? true
    }

    private static func comparatorMatch(
        for comparator: KeyPathComparator<Track>
    ) -> (field: TrackSortField, ascending: Bool)? {
        for field in allCases where field != .custom {
            if comparator == field.getComparator(ascending: true) {
                return (field, true)
            }
            if comparator == field.getComparator(ascending: false) {
                return (field, false)
            }
        }

        let aliases: [(TrackSortField, Bool, KeyPathComparator<Track>)] = [
            (.discNumber, true, KeyPathComparator(\Track.normalizedDiscNumber, order: .forward)),
            (.discNumber, false, KeyPathComparator(\Track.normalizedDiscNumber, order: .reverse)),
            (.dateAdded, true, KeyPathComparator(\Track.sortableDateAdded, order: .forward)),
            (.dateAdded, false, KeyPathComparator(\Track.sortableDateAdded, order: .reverse))
        ]
        return aliases.first { $0.2 == comparator }.map { ($0.0, $0.1) }
    }

    /// The UserDefaults storage key (matches rawValue).
    var storageKey: String { rawValue }

    /// Look up a sort field from its storage key.
    static func from(storageKey: String) -> TrackSortField? {
        TrackSortField(rawValue: storageKey)
    }
}

enum TrackSortPreferences {
    static let globalKey = "trackTableSortOrder"

    static func loadGlobal() -> [KeyPathComparator<Track>] {
        guard let savedSort = UserDefaults.standard.dictionary(forKey: globalKey),
              let key = savedSort["key"] as? String,
              let ascending = savedSort["ascending"] as? Bool,
              let field = TrackSortField.from(storageKey: key) else {
            return [KeyPathComparator(\Track.title, order: .forward)]
        }
        return [field.getComparator(ascending: ascending)]
    }

    static func save(_ sortOrder: [KeyPathComparator<Track>], key: String = globalKey) {
        let field = TrackSortField.detect(from: sortOrder)
        let ascending = TrackSortField.isAscending(from: sortOrder)
        UserDefaults.standard.set(["key": field.storageKey, "ascending": ascending], forKey: key)
    }
}

// MARK: - TrackTableOptionsDropdown

struct TrackTableOptionsDropdown: View {
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var tableRowSize: TableRowSize
    private let playlistID: UUID?
    private let showCustomSort: Bool
    private let usesGlobalSortOrder: Bool
    private let showsArtistGroupingOptions: Bool
    @State private var isCustomSort = false

    @AppStorage("groupArtistTracksByAlbum")
    private var groupsArtistTracksByAlbum = true

    @AppStorage("artistAlbumGroupsAscending")
    private var artistAlbumGroupsAscending = true

    @AppStorage("artistAlbumGroupSortField")
    private var artistAlbumGroupSortField: ArtistAlbumGroupSortField = .albumName

    init(
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>,
        playlistID: UUID? = nil,
        showCustomSort: Bool = false,
        usesGlobalSortOrder: Bool = true,
        showsArtistGroupingOptions: Bool = false
    ) {
        self._sortOrder = sortOrder
        self._tableRowSize = tableRowSize
        self.playlistID = playlistID
        self.showCustomSort = showCustomSort
        self.usesGlobalSortOrder = usesGlobalSortOrder
        self.showsArtistGroupingOptions = showsArtistGroupingOptions
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

    private var canChangeSortOrder: Bool {
        !isCustomSort && TrackSortField.sortFields.contains(currentSortField)
    }

    var body: some View {
        Menu {
            Section("Sort tracks by") {
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

            if showsArtistGroupingOptions {
                Divider()

                Section("Group tracks by") {
                    Toggle("None", isOn: Binding(
                        get: { !groupsArtistTracksByAlbum },
                        set: { _ in groupsArtistTracksByAlbum = false }
                    ))
                    Toggle("Album", isOn: Binding(
                        get: { groupsArtistTracksByAlbum },
                        set: { _ in groupsArtistTracksByAlbum = true }
                    ))

                    Menu("Sort groups by") {
                        Section("Sort groups by") {
                            ForEach(ArtistAlbumGroupSortField.allCases, id: \.self) { field in
                                Toggle(field.displayName, isOn: Binding(
                                    get: { artistAlbumGroupSortField == field },
                                    set: { _ in artistAlbumGroupSortField = field }
                                ))
                            }
                        }

                        Divider()

                        Section("Sort order") {
                            Toggle("Ascending", isOn: Binding(
                                get: { artistAlbumGroupsAscending },
                                set: { _ in artistAlbumGroupsAscending = true }
                            ))
                            Toggle("Descending", isOn: Binding(
                                get: { !artistAlbumGroupsAscending },
                                set: { _ in artistAlbumGroupsAscending = false }
                            ))
                        }
                    }
                    .disabled(!groupsArtistTracksByAlbum)
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
            .disabled(!canChangeSortOrder)

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
            Image(systemName: Icons.sortMenu)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .sortMenuChrome(help: String(localized: "Sort and display options"))
        .onAppear {
            syncCustomSortState()
        }
        .onChange(of: sortOrder) {
            // When parent updates sortOrder (e.g. playlist switch), re-sync custom state
            syncCustomSortState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .trackTableSortChanged)) { notification in
            guard usesGlobalSortOrder || playlistID != nil else { return }

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
        guard usesGlobalSortOrder || playlistID != nil else {
            sortOrder = [newComparator]
            return
        }
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

        guard usesGlobalSortOrder || playlistID != nil else {
            sortOrder = [newComparator]
            return
        }

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
