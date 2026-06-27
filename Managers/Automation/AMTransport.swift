//
// AutomationManager extension - Transport
//
// Playback transport commands (play/pause, navigation, seek, volume, shuffle,
// repeat, favorite) used by the transport App Intents. PlaybackManager has no
// standalone play()/pause(), so those are synthesized from togglePlayPause()
// guarded on isPlaying.
//

import Foundation

@MainActor
extension AutomationManager {
    func playPause() {
        playback?.togglePlayPause()
    }

    func play() {
        guard let playback, !playback.isPlaying else { return }
        playback.togglePlayPause()
    }

    func pause() {
        guard let playback, playback.isPlaying else { return }
        playback.togglePlayPause()
    }

    func nextTrack() {
        playlist?.playNextTrack()
    }

    func previousTrack() {
        playlist?.playPreviousTrack()
    }

    func seek(toSeconds seconds: Double) {
        playback?.seekTo(time: max(0, seconds))
    }

    func skip(bySeconds delta: Double) {
        guard let playback else { return }
        playback.seekTo(time: max(0, playback.actualCurrentTime + delta))
    }

    /// Accepts a 0-100 percentage; PlaybackManager clamps the 0-1 value internally.
    func setVolume(percent: Int) {
        let clamped = max(0, min(100, percent))
        playback?.setVolume(Float(clamped) / 100)
    }

    func toggleShuffle() {
        playlist?.toggleShuffle()
    }

    func setShuffle(_ enabled: Bool) {
        guard let playlist, playlist.isShuffleEnabled != enabled else { return }
        playlist.toggleShuffle()
    }

    /// PlaylistManager only exposes a cycling toggle (off -> all -> one -> off),
    /// so step it until it lands on the requested mode. Bounded to the three
    /// cases so a mismatch can never spin.
    func setRepeatMode(_ mode: RepeatMode) {
        guard let playlist else { return }
        var steps = 0
        while playlist.repeatMode != mode && steps < 3 {
            playlist.toggleRepeatMode()
            steps += 1
        }
    }

    /// Toggles favorite for the current track. Returns false when nothing is playing.
    @discardableResult
    func toggleFavoriteCurrent() -> Bool {
        guard let track = playback?.currentTrack else { return false }
        playlist?.toggleFavorite(for: track)
        return true
    }
}
