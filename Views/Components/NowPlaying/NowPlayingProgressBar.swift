//
// NowPlayingProgressBar
//
// A compact, self-contained, artwork-tinted seek bar shared by the mini player
// and immersive mode.
//
// The slider logic mirrors PlayerView.progressSlider. That implementation is
// private to PlayerView, so rather than refactor the main player we duplicate
// the small amount of seek logic here to keep the change contained.
//

import SwiftUI
import AppKit

struct NowPlayingProgressBar: View {
    /// Fill color for the progress track / handle (artwork dominant color from the host).
    let tint: Color
    var scale: CGFloat = 1

    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playbackProgressState: PlaybackProgressState

    /// A lightened version of the tint so the filled progress stays visible even
    /// when the artwork's dominant color is dark.
    private var fillColor: Color {
        let base = NSColor(tint).usingColorSpace(.sRGB) ?? NSColor(tint)
        let lightened = base.blended(withFraction: 0.45, of: .white) ?? base
        return Color(nsColor: lightened)
    }

    @State private var isDraggingProgress = false
    @State private var tempProgressValue: Double = 0
    @State private var hoveredOverProgress = false

    var body: some View {
        HStack(spacing: 8 * scale) {
            Text(HelperUtils.formattedDuration(isDraggingProgress ? tempProgressValue : playbackProgressState.currentTime))
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .monospacedDigit()
                .frame(width: timeLabelWidth, alignment: .trailing)

            progressSlider

            Text(HelperUtils.formattedDuration(playbackManager.currentTrack?.duration ?? 0))
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .monospacedDigit()
                .frame(width: timeLabelWidth, alignment: .leading)
        }
    }

    private var progressSlider: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 4 * scale)

                // Progress track
                RoundedRectangle(cornerRadius: 2)
                    .fill(fillColor)
                    .frame(width: geometry.size.width * progressPercentage, height: 4 * scale)
                    .animation(isDraggingProgress ? .none : .easeInOut(duration: 0.2), value: progressPercentage)

                // Drag handle
                Circle()
                    .fill(fillColor)
                    .frame(width: 10 * scale, height: 10 * scale)
                    .opacity(isDraggingProgress || hoveredOverProgress ? 1.0 : 0.0)
                    .offset(x: (geometry.size.width * progressPercentage) - (5 * scale))
                    .animation(isDraggingProgress ? .none : .easeInOut(duration: 0.2), value: progressPercentage)
                    .animation(.easeInOut(duration: 0.15), value: hoveredOverProgress)
            }
            .contentShape(Rectangle())
            .gesture(progressDragGesture(in: geometry))
            .onTapGesture { value in
                handleProgressTap(at: value.x, in: geometry.size.width)
            }
            .onHover { hovering in
                hoveredOverProgress = hovering
            }
        }
        .frame(height: 10 * scale)
        .disabled(playbackManager.currentTrack == nil)
    }

    // MARK: - Helpers

    private var timeLabelWidth: CGFloat {
        ((playbackManager.currentTrack?.duration ?? 0) >= 3600 ? 50 : 36) * scale
    }

    private var progressPercentage: Double {
        guard let duration = playbackManager.currentTrack?.duration, duration > 0 else { return 0 }

        if isDraggingProgress {
            return min(1, max(0, tempProgressValue / duration))
        } else {
            return min(1, max(0, playbackProgressState.currentTime / duration))
        }
    }

    private func progressDragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDraggingProgress {
                    isDraggingProgress = true
                }
                let percentage = max(0, min(1, value.location.x / geometry.size.width))
                let duration = HelperUtils.sanitizedDuration(playbackManager.currentTrack?.duration ?? 0)
                tempProgressValue = percentage * duration
            }
            .onEnded { value in
                let percentage = max(0, min(1, value.location.x / geometry.size.width))
                let duration = HelperUtils.sanitizedDuration(playbackManager.currentTrack?.duration ?? 0)
                let newTime = percentage * duration
                playbackManager.seekTo(time: newTime)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isDraggingProgress = false
                }
            }
    }

    private func handleProgressTap(at x: CGFloat, in width: CGFloat) {
        guard playbackManager.currentTrack != nil else { return }
        let percentage = max(0, min(1, x / width))
        let duration = HelperUtils.sanitizedDuration(playbackManager.currentTrack?.duration ?? 0)
        let newTime = percentage * duration
        playbackManager.seekTo(time: newTime)
    }
}
