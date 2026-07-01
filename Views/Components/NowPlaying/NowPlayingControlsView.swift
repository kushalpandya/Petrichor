//
// NowPlayingControlsView
//
// Compact, artwork-tinted transport row shared by the mini player and immersive
// mode. Reuses the same manager calls and button styling as PlayerView
// (ControlButtonStyle, hoverEffect).
//

import SwiftUI
import AppKit

struct NowPlayingControlsView: View {
    /// Fill color for the play/pause button (artwork dominant color from the host).
    let tint: Color
    /// Legible, mode-adjusted color for the active shuffle/repeat states.
    var accent: Color
    /// Color for the prev/next transport icons.
    var transport: Color
    /// Base color for inactive/secondary icons (white on the mini player's dark
    /// scrim; adaptive in immersive mode).
    var neutral: Color = .white
    var scale: CGFloat = 1

    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var playButtonPressed = false

    private var hasCurrentTrack: Bool {
        playbackManager.currentTrack != nil
    }

    /// A lightened version of the tint, used as the play/pause button's backdrop
    /// shadow so it reads as a soft glow of the button's own (artwork) color.
    private var lightenedTint: Color {
        let base = NSColor(tint).usingColorSpace(.sRGB) ?? NSColor(tint)
        let lightened = base.blended(withFraction: 0.5, of: .white) ?? base
        return Color(nsColor: lightened)
    }

    var body: some View {
        HStack(spacing: 20 * scale) {
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
                .font(.system(size: 13 * scale, weight: .medium))
                .foregroundColor(playlistManager.isShuffleEnabled ? accent : neutral.opacity(0.65))
                .frame(width: 24 * scale, height: 24 * scale)
                .activeControlIndicator(isActive: playlistManager.isShuffleEnabled, color: accent, scale: scale)
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
                .font(.system(size: 16 * scale, weight: .medium))
                .foregroundColor(transport)
                .frame(width: 24 * scale, height: 24 * scale)
                .shadow(color: lightenedTint.opacity(0.6), radius: 4 * scale, x: 0, y: 1 * scale)
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
                .frame(width: 42 * scale, height: 42 * scale)
                .background(
                    Circle()
                        .fill(tint)
                        .shadow(color: lightenedTint.opacity(0.6), radius: 7 * scale, x: 0, y: 2 * scale)
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
                .font(.system(size: 16 * scale, weight: .medium))
                .foregroundColor(transport)
                .frame(width: 24 * scale, height: 24 * scale)
                .shadow(color: lightenedTint.opacity(0.6), radius: 4 * scale, x: 0, y: 1 * scale)
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
                .font(.system(size: 13 * scale, weight: .medium))
                .foregroundColor(playlistManager.repeatMode != .off ? accent : neutral.opacity(0.65))
                .frame(width: 24 * scale, height: 24 * scale)
                .activeControlIndicator(isActive: playlistManager.repeatMode != .off, color: accent, scale: scale)
        })
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(!hasCurrentTrack)
        .help(playlistManager.repeatMode.tooltip)
    }
}
