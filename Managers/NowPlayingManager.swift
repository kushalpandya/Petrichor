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

        // Set the artwork
        if let artworkData = track.artworkData, let image = NSImage(data: artworkData) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in
                NSImage(data: artworkData)!
            }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        // Set the duration and current time
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime

        // Set the playback rate (0.0 = paused, 1.0 = playing)
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        // Update the now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    // MARK: - Remote Command Center

    private func setupRemoteCommandCenter() {
        // Get the shared command center
        let commandCenter = MPRemoteCommandCenter.shared()

        // Remove any existing handlers
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
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
