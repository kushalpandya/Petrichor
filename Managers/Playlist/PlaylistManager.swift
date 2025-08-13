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
    @Published var trackToAddToNewPlaylist: Track?
    @Published var newPlaylistName = ""

    enum QueueSource {
        case library
        case folder
        case playlist
    }

    // MARK: - Private/Internal Properties
    private var shuffledIndices: [Int] = []
    internal var libraryManager: LibraryManager?

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

    /// Toggle favorite status for a track
    func toggleFavorite(for track: Track) {
        // Simply toggle the favorite status - the system will handle the rest
        Task {
            await updateTrackFavoriteStatus(track: track, isFavorite: !track.isFavorite)
        }
    }

    /// Add track to a specific playlist by ID
    func addTrackToPlaylist(track: Track, playlistID: UUID) {
        if let playlist = playlists.first(where: { $0.id == playlistID }) {
            updateTrackInPlaylist(track: track, playlist: playlist, add: true)
        }
    }

    /// Remove track from a specific playlist by ID
    func removeTrackFromPlaylist(track: Track, playlistID: UUID) {
        if let playlist = playlists.first(where: { $0.id == playlistID }) {
            updateTrackInPlaylist(track: track, playlist: playlist, add: false)
        }
    }
    
    func updateSmartPlaylistCounts() {
        Task {
            for index in playlists.indices {
                if playlists[index].type == .smart {
                    let count = await libraryManager?.databaseManager.getSmartPlaylistTrackCount(playlists[index]) ?? 0
                    
                    await MainActor.run {
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
    
    /// Sort playlists according to type and predefined order
    func sortPlaylists(smart: [Playlist], regular: [Playlist]) -> [Playlist] {
        // Combine all playlists and sort by creation date (oldest first)
        let allPlaylists = smart + regular
        return allPlaylists.sorted { $0.dateCreated < $1.dateCreated }
    }
    
    /// Get all playlists that a track belongs to
    func getPlaylistsContainingTrack(_ track: Track) -> [Playlist] {
        playlists.filter { playlist in
            playlist.tracks.contains { $0.id == track.id }
        }
    }
    
    /// Check if a playlist name already exists
    func playlistExists(withName name: String) -> Bool {
        playlists.contains { $0.name.lowercased() == name.lowercased() }
    }
}
