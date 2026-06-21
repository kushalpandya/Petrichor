//
// MiniPlayerControlsView
//
// Compact transport row for the mini player window. Reuses the same manager
// calls and button styling as PlayerView (ControlButtonStyle, hoverEffect).
//

import SwiftUI

struct MiniPlayerControlsView: View {
    /// Fill color for the play/pause button (artwork dominant color from the host).
    let tint: Color

    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var playButtonPressed = false

    private var hasCurrentTrack: Bool {
        playbackManager.currentTrack != nil
    }

    var body: some View {
        HStack(spacing: 20) {
            shuffleButton
            previousButton
            playPauseButton
            nextButton
            repeatButton
        }
    }

    private var shuffleButton: some View {
        Button(action: {
            playlistManager.toggleShuffle()
        }, label: {
            Image(systemName: Icons.shuffleFill)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(playlistManager.isShuffleEnabled ? tint : Color.white.opacity(0.65))
                .frame(width: 24, height: 24)
        })
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(!hasCurrentTrack)
        .help(playlistManager.isShuffleEnabled ? String(localized: "Disable Shuffle") : String(localized: "Enable Shuffle"))
    }

    private var previousButton: some View {
        Button(action: {
            playlistManager.playPreviousTrack()
        }, label: {
            Image(systemName: Icons.backwardFill)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
        })
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(!hasCurrentTrack)
        .help("Previous")
    }

    private var playPauseButton: some View {
        Button(action: {
            playbackManager.togglePlayPause()
        }, label: {
            PlayPauseIcon(isPlaying: playbackManager.isPlaying)
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(tint)
                        .shadow(color: tint.opacity(0.35), radius: 6, x: 0, y: 3)
                )
        })
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(scale: 1.1)
        .scaleEffect(playButtonPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: AnimationDuration.quickDuration), value: playButtonPressed)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                playButtonPressed = pressing
            },
            perform: {}
        )
        .disabled(!hasCurrentTrack)
        .help(playbackManager.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
    }

    private var nextButton: some View {
        Button(action: {
            playlistManager.playNextTrack()
        }, label: {
            Image(systemName: Icons.forwardFill)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
        })
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(!hasCurrentTrack)
        .help("Next")
    }

    private var repeatButton: some View {
        Button(action: {
            playlistManager.toggleRepeatMode()
        }, label: {
            Image(systemName: Icons.repeatIcon(for: playlistManager.repeatMode))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(playlistManager.repeatMode != .off ? tint : Color.white.opacity(0.65))
                .frame(width: 24, height: 24)
        })
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(!hasCurrentTrack)
        .help(playlistManager.repeatMode.tooltip)
    }
}
