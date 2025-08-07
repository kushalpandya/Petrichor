import Foundation

class FolderNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isWatchFolder: Bool // True if this is the root watch folder

    @Published var children: [FolderNode] = []
    @Published var isExpanded: Bool = false
    @Published var isLoading: Bool = false

    // Counts for immediate contents only
    var immediateTrackCount: Int = 0
    var immediateFolderCount: Int {
        children.count
    }

    // Cached database folder reference if this corresponds to a watched folder
    var databaseFolder: Folder?

    init(url: URL, name: String? = nil, isWatchFolder: Bool = false) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.isWatchFolder = isWatchFolder
    }

    // Helper to check if this folder contains any tracks (immediate or nested)
    func containsTracks(using libraryManager: LibraryManager) -> Bool {
        // Check immediate tracks
        if immediateTrackCount > 0 {
            return true
        }

        // Check if any child folders contain tracks
        return children.contains { child in
            child.containsTracks(using: libraryManager)
        }
    }

    // Helper to get all tracks in this folder (immediate only)
    func getImmediateTracks(using libraryManager: LibraryManager) -> [Track] {
        let allTracks: [Track]
        
        if let dbFolder = databaseFolder {
            allTracks = libraryManager.getTracksInFolder(dbFolder)
        } else {
            guard let parentFolder = libraryManager.folders.first(where: {
                self.url.path.starts(with: $0.url.path)
            }) else {
                return []
            }
            allTracks = libraryManager.getTracksInFolder(parentFolder)
        }
        
        return allTracks.filter { track in
            track.url.deletingLastPathComponent().path == self.url.path
        }
    }
}

// Make it Equatable for selection tracking
extension FolderNode: Equatable {
    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.id == rhs.id
    }
}

// Make it Hashable for use in Sets
extension FolderNode: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
