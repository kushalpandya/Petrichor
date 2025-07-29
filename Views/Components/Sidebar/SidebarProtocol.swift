import SwiftUI

// MARK: - Sidebar Item Protocol

protocol SidebarItem: Identifiable, Equatable {
    var id: UUID { get }
    var title: String { get }
    var subtitle: String? { get }
    var icon: String? { get }
    var count: Int? { get }
    var isEditable: Bool { get }
}

// Default implementation
extension SidebarItem {
    var isEditable: Bool { false }
}

// MARK: - Home Sidebar Item

struct HomeSidebarItem: SidebarItem {
    let id: UUID
    let title: String
    let subtitle: String?
    let icon: String?
    var count: Int?
    let isEditable: Bool = false
    let type: HomeItemType?
    
    // Item source
    enum ItemSource {
        case fixed(HomeItemType)
        case pinned(PinnedItem)
    }
    let source: ItemSource

    enum HomeItemType: CaseIterable {
        case discover
        case tracks
        case artists
        case albums

        var stableID: UUID {
            switch self {
            case .discover:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            case .tracks:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            case .artists:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            case .albums:
                return UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            }
        }

        var title: String {
            switch self {
            case .discover: return "Discover"
            case .tracks: return "Tracks"
            case .artists: return "Artists"
            case .albums: return "Albums"
            }
        }

        var icon: String {
            switch self {
            case .discover: return Icons.sparkles
            case .tracks: return Icons.musicNote
            case .artists: return Icons.person2Fill
            case .albums: return Icons.opticalDiscFill
            }
        }
    }

    // Init for fixed items
    init(type: HomeItemType, trackCount: Int? = nil, artistCount: Int? = nil, albumCount: Int? = nil) {
        self.id = type.stableID
        self.type = type
        self.source = .fixed(type)
        self.title = type.title
        self.icon = type.icon

        // Set subtitle based on type
        switch type {
        case .discover:
            if let count = trackCount {
                self.subtitle = "\(count) songs"
            } else {
                self.subtitle = "0 Songs"
            }
        case .tracks:
            if let count = trackCount {
                self.subtitle = "\(count) songs"
            } else {
                self.subtitle = "0 songs"
            }
        case .artists:
            if let count = artistCount {
                self.subtitle = "\(count) artists"
            } else {
                self.subtitle = "0 artists"
            }
        case .albums:
            if let count = albumCount {
                self.subtitle = "\(count) albums"
            } else {
                self.subtitle = "0 albums"
            }
        }
    }
    
    // Init for pinned items
    init(pinnedItem: PinnedItem, trackCount: Int = 0) {
        self.id = UUID(uuidString: "pinned-\(pinnedItem.id ?? 0)") ?? UUID()
        self.type = nil
        self.source = .pinned(pinnedItem)
        self.title = pinnedItem.displayName
        self.subtitle = "\(trackCount) \(trackCount == 1 ? "song" : "songs")"
        self.icon = pinnedItem.iconName
    }
}

// MARK: - Equatable Conformance
extension HomeSidebarItem: Equatable {
    static func == (lhs: HomeSidebarItem, rhs: HomeSidebarItem) -> Bool {
        // Compare by ID first (most common case)
        if lhs.id != rhs.id {
            return false
        }
        
        // Then compare by source
        switch (lhs.source, rhs.source) {
        case (.fixed(let lhsType), .fixed(let rhsType)):
            return lhsType == rhsType
        case (.pinned(let lhsItem), .pinned(let rhsItem)):
            return lhsItem.id == rhsItem.id
        default:
            return false
        }
    }
}

// MARK: - Library Sidebar Item

struct LibrarySidebarItem: SidebarItem {
    let id: UUID
    let title: String
    let subtitle: String?
    let icon: String?
    let count: Int?
    let filterType: LibraryFilterType
    let filterName: String
    let isEditable: Bool = false

    init(filterItem: LibraryFilterItem) {
        self.id = filterItem.id
        self.title = filterItem.name
        self.subtitle = "\(filterItem.count) \(filterItem.count == 1 ? "song" : "songs")"
        self.icon = Self.getIcon(for: filterItem.filterType, isAllItem: false)
        self.count = nil
        self.filterType = filterItem.filterType
        self.filterName = filterItem.name
    }

    // Special "All" item
    init(allItemFor filterType: LibraryFilterType, count: Int) {
        self.id = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", filterType.stableIndex))") ?? UUID()
        self.title = "All \(filterType.rawValue)"
        self.subtitle = "\(count) \(count == 1 ? "song" : "songs")"
        self.icon = Self.getIcon(for: filterType, isAllItem: true)
        self.count = nil
        self.filterType = filterType
        self.filterName = ""
    }

    private static func getIcon(for filterType: LibraryFilterType, isAllItem: Bool) -> String {
        isAllItem ? filterType.allItemIcon : filterType.icon
    }
}

// MARK: - Playlist Sidebar Item

struct PlaylistSidebarItem: SidebarItem {
    let id: UUID
    let title: String
    let subtitle: String?
    let icon: String?
    let count: Int?
    let playlist: Playlist
    let isEditable: Bool

    init(playlist: Playlist) {
        self.id = playlist.id
        self.title = playlist.name
        self.icon = Icons.defaultPlaylistIcon(for: playlist)
        self.playlist = playlist
        self.isEditable = playlist.isUserEditable

        // Set subtitle and count based on playlist type
        if playlist.type == .smart {
            let trackCount = playlist.tracks.count
            if let limit = playlist.trackLimit {
                self.subtitle = "\(trackCount) / \(limit) songs"
            } else {
                self.subtitle = "\(trackCount) songs"
            }
            self.count = nil
        } else {
            self.subtitle = "\(playlist.tracks.count) songs"
            self.count = nil
        }
    }
}

// MARK: - Folder Node Sidebar Item

struct FolderNodeSidebarItem: SidebarItem {
    let id: UUID
    let title: String
    let subtitle: String?
    let icon: String?
    let count: Int?
    let folderNode: FolderNode
    let isEditable: Bool = false

    init(folderNode: FolderNode) {
        self.id = folderNode.id
        self.title = folderNode.name
        self.folderNode = folderNode

        if folderNode.children.isEmpty {
            self.icon = Icons.folderFill
        } else {
            self.icon = folderNode.isExpanded ? Icons.folderFillBadgeMinus : Icons.folderFillBadgePlus
        }

        if folderNode.immediateFolderCount > 0 && folderNode.immediateTrackCount > 0 {
            self.subtitle = "\(folderNode.immediateFolderCount) folders, \(folderNode.immediateTrackCount) tracks"
        } else if folderNode.immediateFolderCount > 0 {
            self.subtitle = "\(folderNode.immediateFolderCount) folders"
        } else if folderNode.immediateTrackCount > 0 {
            self.subtitle = "\(folderNode.immediateTrackCount) tracks"
        } else {
            self.subtitle = nil
        }

        self.count = nil
    }
}
