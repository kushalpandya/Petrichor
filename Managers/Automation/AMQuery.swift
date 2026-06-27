//
// AutomationManager extension - Query
//
// Read-only snapshot of the current playback state, returned by the
// CurrentTrack App Intent so Shortcuts flows can branch on what's playing.
//

import Foundation

@MainActor
extension AutomationManager {
    func nowPlayingSnapshot() -> NowPlayingSnapshot? {
        guard let playback, let track = playback.currentTrack else { return nil }
        return NowPlayingSnapshot(
            title: track.title,
            artist: track.displayArtist,
            album: track.displayAlbum,
            duration: track.duration,
            position: playback.actualCurrentTime,
            isPlaying: playback.isPlaying,
            isFavorite: track.isFavorite
        )
    }
}

/// Plain transfer struct so the App Intents layer (AutomationEntities) stays
/// decoupled from the Track model.
struct NowPlayingSnapshot {
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let position: Double
    let isPlaying: Bool
    let isFavorite: Bool
}
