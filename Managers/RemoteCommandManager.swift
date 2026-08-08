//
// RemoteCommandManager class
//
// Routes the system transport commands (Control Center, media keys, AirPlay
// remote) to Petrichor's playback and queue managers. The Now Playing info tile
// is published by the engine - see `PlaybackEngine.setNowPlayingMetadata`.
//

import Foundation
import MediaPlayer

class RemoteCommandManager {
    init() {
        setupRemoteCommandCenter()
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

        // Add handler for next track command, refused while streaming: a stream is not a queue member.
        commandCenter.nextTrackCommand.addTarget { [weak playlistManager, weak audioPlayer] _ in
            guard let playlistManager = playlistManager, audioPlayer?.currentStation == nil else {
                return .commandFailed
            }

            playlistManager.playNextTrack()
            return .success
        }

        // Add handler for previous track command
        commandCenter.previousTrackCommand.addTarget { [weak playlistManager, weak audioPlayer] _ in
            guard let playlistManager = playlistManager, audioPlayer?.currentStation == nil else {
                return .commandFailed
            }

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
