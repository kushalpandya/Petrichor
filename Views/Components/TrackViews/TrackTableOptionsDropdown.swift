import SwiftUI

// MARK: - Sort Field Enum

enum TrackSortField: String, CaseIterable {
    case trackNumber = "trackNumber"
    case discNumber = "discNumber"
    case favorite = "favorite"
    case title = "title"
    case artist = "artist"
    case album = "album"
    case genre = "genre"
    case year = "year"
    case composer = "composer"
    case filename = "filename"
    case duration = "duration"
    case dateAdded = "dateAdded"
    
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
            .dateAdded: KeyPathComparator(\Track.dateAdded, order: ascending ? .forward : .reverse)
        ]
        
        return sortComparators[self] ?? KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse)
    }
    
    static var sortFields: [TrackSortField] {
        [.trackNumber, .discNumber, .favorite, .title, .artist, .album, .genre, .year, .composer, .filename, .duration, .dateAdded]
    }
}

// MARK: - TrackTableOptionsDropdown

struct TrackTableOptionsDropdown: View {
    @Binding var sortOrder: [KeyPathComparator<Track>]
    @Binding var tableRowSize: TableRowSize
    private let playlistID: UUID?
    
    init(
        sortOrder: Binding<[KeyPathComparator<Track>]>,
        tableRowSize: Binding<TableRowSize>,
        playlistID: UUID? = nil
    ) {
        self._sortOrder = sortOrder
        self._tableRowSize = tableRowSize
        self.playlistID = playlistID
    }
    
    private var currentSortField: TrackSortField {
        guard let firstSort = sortOrder.first else { return .title }
        
        let sortString = String(describing: firstSort)
        
        let sortKeyMap = [
            "dateAdded": TrackSortField.dateAdded,
            "sortableTrackNumber": TrackSortField.trackNumber,
            "sortableDiscNumber": TrackSortField.discNumber,
            "sortableIsFavorite": TrackSortField.favorite,
            "title": TrackSortField.title,
            "artist": TrackSortField.artist,
            "album": TrackSortField.album,
            "genre": TrackSortField.genre,
            "year": TrackSortField.year,
            "composer": TrackSortField.composer,
            "filename": TrackSortField.filename,
            "duration": TrackSortField.duration
        ]
        
        for (key, field) in sortKeyMap {
            if sortString.contains(key) {
                return field
            }
        }
        
        return .title
    }
    
    private var isAscending: Bool {
        guard let firstSort = sortOrder.first else { return true }
        return String(describing: firstSort).contains("forward")
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
        .fixedSize()
        .hoverEffect(activeBackgroundColor: Color(NSColor.controlColor))
        .help("Sort and display options")
        .onReceive(NotificationCenter.default.publisher(for: .trackTableSortChanged)) { notification in
            if notification.userInfo?["fromTable"] as? Bool == true,
               let newSortOrder = notification.userInfo?["sortOrder"] as? [KeyPathComparator<Track>] {
                sortOrder = newSortOrder
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
    
    private func setSortField(_ field: TrackSortField) {
        let newComparator = field.getComparator(ascending: isAscending)
        
        NotificationCenter.default.post(
            name: .trackTableSortChanged,
            object: nil,
            userInfo: ["sortOrder": [newComparator], "userDefaultsKey": "trackTableSortOrder"]
        )
    }
    
    private func setSortAscending(_ ascending: Bool) {
        let newComparator = currentSortField.getComparator(ascending: ascending)
        
        let userDefaultsKey = playlistID != nil ? "playlistTableSortOrder" : "trackTableSortOrder"
        
        NotificationCenter.default.post(
            name: .trackTableSortChanged,
            object: nil,
            userInfo: ["sortOrder": [newComparator], "userDefaultsKey": userDefaultsKey]
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
