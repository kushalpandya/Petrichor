//
// PlaylistManager class
//
// This class handles all the Playlist operations done by the app, note that this file only
// contains core methods, the domain-specific logic is spread across extension files within this
// directory where each file is prefixed with `PM`.
//

import Foundation

class PlaylistManager: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var currentPlaylist: Playlist?
    @Published var isShuffleEnabled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var currentQueue: [Track] = []
    @Published var currentQueueIndex: Int = -1
    @Published var currentQueueSource: QueueSource = .library
    @Published var showingCreatePlaylistModal = false
    @Published var tracksToAddToNewPlaylist: [Track] = []
    @Published var newPlaylistName = ""
    // Smart playlist editor: presented for both creating (toEdit == nil) and editing.
    @Published var showingSmartPlaylistEditor = false
    @Published var smartPlaylistToEdit: Playlist?
    // Regular playlist editor (name + song selection): presented for both creating
    // (toEdit == nil) and editing an existing playlist.
    @Published var showingRegularPlaylistEditor = false
    @Published var regularPlaylistToEdit: Playlist?

    enum QueueSource {
        case library
        case folder
        case playlist
    }

    // MARK: - Private/Internal Properties
    internal var libraryManager: LibraryManager?

    /// Smart playlists whose tracks are currently being loaded, to collapse concurrent
    /// duplicate loads (e.g. PlaylistDetailView firing onAppear + onChange together).
    /// Mutated only on the main actor.
    internal var loadingSmartPlaylistIDs: Set<UUID> = []

    // MARK: - Dependencies
    internal weak var audioPlayer: PlaybackManager?

    // MARK: - Initialization
    init() {
        // Don't load playlists yet - wait until libraryManager is set
    }

    func setAudioPlayer(_ player: PlaybackManager) {
        self.audioPlayer = player
    }

    func setLibraryManager(_ manager: LibraryManager) {
        self.libraryManager = manager
        Logger.info("Library manager set, loading playlists...")
        loadPlaylists()
    }

    // MARK: - Convenience Methods

    /// Toggle favorite status for a single track
    func toggleFavorite(for track: Track, currentState: Bool? = nil) {
        let finalState: Bool?
        if let currentState = currentState {
            finalState = !currentState
        } else {
            finalState = nil
        }
        toggleFavorite(for: [track], setTo: finalState)
    }

    /// Toggle favorite status for multiple tracks
    func toggleFavorite(for tracks: [Track], setTo finalState: Bool? = nil) {
        Task {
            for track in tracks {
                let isFavorite: Bool
                if let finalState = finalState {
                    isFavorite = finalState
                } else {
                    isFavorite = !track.isFavorite
                }
                await updateTrackFavoriteStatus(track: track, isFavorite: isFavorite)
            }
        }
    }

    /// Remove track from a specific playlist by ID
    func removeTrackFromPlaylist(track: Track, playlistID: UUID) {
        if let playlist = playlists.first(where: { $0.id == playlistID }) {
            updateTrackInPlaylist(track: track, playlist: playlist, add: false)
        }
    }
    
    func updateSmartPlaylistCounts() {
        // Only auto-updating smart playlists need their count computed from criteria.
        // Frozen playlists already carry the correct count from their persisted snapshot.
        let autoSmart = playlists.filter { $0.type == .smart && ($0.smartCriteria?.autoUpdate ?? true) }
        guard let dbManager = libraryManager?.databaseManager, !autoSmart.isEmpty else { return }

        // One batched read for all counts instead of N separate awaited reads.
        Task {
            let counts = await dbManager.getSmartPlaylistTrackCounts(autoSmart)
            await MainActor.run {
                for (id, count) in counts {
                    if let index = self.playlists.firstIndex(where: { $0.id == id }) {
                        self.playlists[index].trackCount = count
                    }
                }
            }
        }
    }
    
    /// Load all playlists from database
    func loadPlaylists() {
        guard let dbManager = libraryManager?.databaseManager else {
            return
        }
        
        let savedPlaylists = dbManager.loadAllPlaylists()
        
        let savedSmartPlaylists = savedPlaylists.filter { $0.type == .smart }
        let savedRegularPlaylists = savedPlaylists.filter { $0.type == .regular }
        
        playlists = sortPlaylists(smart: savedSmartPlaylists, regular: savedRegularPlaylists)
        
        updateSmartPlaylistCounts()
    }
    
    /// Ensure tracks are loaded for a playlist
    func loadPlaylistTracks(for playlistId: UUID) {
        guard let playlist = playlists.first(where: { $0.id == playlistId }),
              playlist.type == .regular,
              playlist.tracks.isEmpty,
              let dbManager = libraryManager?.databaseManager else {
            return
        }
        
        let tracks = dbManager.loadTracksForPlaylist(playlistId)
        
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].tracks = tracks
        }
    }
    
    /// Get tracks for a playlist, loading them if needed
    func getPlaylistTracks(_ playlist: Playlist) -> [Track] {
        if playlist.type == .smart {
            // Smart playlists are already handled differently
            return playlist.tracks
        }
        
        // For regular playlists, load tracks if not already loaded
        if playlist.tracks.isEmpty {
            if let dbManager = libraryManager?.databaseManager {
                let tracks = dbManager.loadTracksForPlaylist(playlist.id)
                
                // Update the playlist with loaded tracks
                if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
                    playlists[index].tracks = tracks
                }
                
                return tracks
            }
        }
        
        return playlist.tracks
    }
    
    /// Sort playlists: smart playlists first (by dateCreated), then regular playlists (by sortOrder, dateCreated as tiebreaker)
    func sortPlaylists(smart: [Playlist], regular: [Playlist]) -> [Playlist] {
        let sortedSmart = smart.sorted { $0.dateCreated < $1.dateCreated }
        let sortedRegular = regular.sorted {
            $0.sortOrder == $1.sortOrder ? $0.dateCreated < $1.dateCreated : $0.sortOrder < $1.sortOrder
        }
        return sortedSmart + sortedRegular
    }

    /// Reorder user playlists and persist the new order
    func reorderPlaylists(_ reorderedPlaylists: [Playlist]) {
        guard let dbManager = libraryManager?.databaseManager else { return }

        playlists = reorderedPlaylists

        Task {
            do {
                try await dbManager.updatePlaylistsOrder(reorderedPlaylists)
            } catch {
                Logger.error("Failed to reorder playlists: \(error)")
            }
        }
    }
}
