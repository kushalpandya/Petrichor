//
// NowPlayingManager class
//
// This class handles the track playback from NowPlaying UI.
//

import Foundation
import AppKit
import MediaPlayer

class NowPlayingManager {
    init() {
        setupRemoteCommandCenter()
    }

    // MARK: - Now Playing Info

    func updateNowPlayingInfo(track: Track, currentTime: Double, isPlaying: Bool) {
        var nowPlayingInfo = [String: Any]()

        // Set the title, artist, and album
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album
        nowPlayingInfo[MPMediaItemPropertyGenre] = track.genre

        // Set the artwork. updateNowPlayingInfo runs on every play/pause/seek and
        // ~1/sec while playing, so cache the MPMediaItemArtwork per track and only
        // decode the image when the track changes (decoding it each call is the
        // expensive part and makes AirPlay receivers redraw).
        if let artwork = artwork(for: track) {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        // Set the duration and current time
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

        // Set the playback rate (0.0 = paused, 1.0 = playing)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Update the now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        // Reflect transport state to the macOS Now Playing widget (it reads this
        // in addition to the playback rate).
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private var cachedArtwork: MPMediaItemArtwork?
    private var cachedArtworkURL: URL?

    private func artwork(for track: Track) -> MPMediaItemArtwork? {
        guard let artworkData = track.artworkData else {
            cachedArtwork = nil
            cachedArtworkURL = nil
            return nil
        }
        if cachedArtworkURL == track.url, let cached = cachedArtwork {
            return cached
        }
        guard let image = NSImage(data: artworkData) else {
            cachedArtwork = nil
            cachedArtworkURL = nil
            return nil
        }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        cachedArtwork = artwork
        cachedArtworkURL = track.url
        return artwork
    }

    /// The remote commands Petrichor handles. Single source of truth for remote
    /// command teardown and registration.
    private var managedCommands: [MPRemoteCommand] {
        let center = MPRemoteCommandCenter.shared()
        return [
            center.playCommand,
            center.pauseCommand,
            center.togglePlayPauseCommand,
            center.nextTrackCommand,
            center.previousTrackCommand,
            center.changePlaybackPositionCommand
        ]
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        // Remove any existing handlers
        for command in managedCommands {
            command.removeTarget(nil)
        }
    }

    func connectRemoteCommandCenter(audioPlayer: PlaybackManager, playlistManager: PlaylistManager) {
        let commandCenter = MPRemoteCommandCenter.shared()

        // Add handler for play command
        commandCenter.playCommand.addTarget { [weak audioPlayer] _ in
            guard let audioPlayer = audioPlayer else { return .commandFailed }

            if !audioPlayer.isPlaying {
                audioPlayer.togglePlayPause()
                return .success
            }
            return .commandFailed
        }

        // Add handler for pause command
        commandCenter.pauseCommand.addTarget { [weak audioPlayer] _ in
            guard let audioPlayer = audioPlayer, audioPlayer.isPlaying else {
                return .commandFailed
            }

            audioPlayer.togglePlayPause()
            return .success
        }

        // Add handler for toggle play/pause command
        commandCenter.togglePlayPauseCommand.addTarget { [weak audioPlayer] _ in
            guard let audioPlayer = audioPlayer else { return .commandFailed }

            audioPlayer.togglePlayPause()
            return .success
        }

        // Add handler for next track command
        commandCenter.nextTrackCommand.addTarget { [weak playlistManager] _ in
            guard let playlistManager = playlistManager else { return .commandFailed }

            playlistManager.playNextTrack()
            return .success
        }

        // Add handler for previous track command
        commandCenter.previousTrackCommand.addTarget { [weak playlistManager] _ in
            guard let playlistManager = playlistManager else { return .commandFailed }

            playlistManager.playPreviousTrack()
            return .success
        }

        // Add handler for seeking
        commandCenter.changePlaybackPositionCommand.addTarget { [weak audioPlayer] event in
            guard let audioPlayer = audioPlayer,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            audioPlayer.seekTo(time: positionEvent.positionTime)
            return .success
        }
    }
}
