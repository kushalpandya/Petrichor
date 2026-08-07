import SwiftUI

/// Carries the `playbackProgressState` subscription alone, so the ~10Hz progress ticks
/// don't re-render the whole player bar.
struct PlayerProgressBar: View {
    let accent: Color

    static let trackWidth: CGFloat = 400

    /// Widest an elapsed/duration label gets: the `H:MM:SS` form used past an hour.
    private static let maxTimeLabelWidth: CGFloat = 56

    /// One constant width for both side slots, wide enough for `H:MM:SS` or CONNECTING.
    /// Anything narrower moves or resizes the bar when either label changes.
    static let sideSlotWidth: CGFloat = max(maxTimeLabelWidth, LiveIndicator.connectingSlotWidth)

    static let preferredWidth: CGFloat = trackWidth + 2 * (sideSlotWidth + 8)

    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playbackProgressState: PlaybackProgressState

    @State private var isDraggingProgress = false
    @State private var tempProgressValue: Double = 0
    @State private var hoveredOverProgress = false

    private var isStream: Bool { playbackManager.hasStation }

    var body: some View {
        HStack(spacing: 8) {
            Text(HelperUtils.formattedDuration(isDraggingProgress ? tempProgressValue : playbackProgressState.currentTime))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: Self.sideSlotWidth, alignment: .trailing)

            if isStream {
                StreamProgressTrack(
                    accent: accent,
                    isBuffering: playbackManager.isBuffering,
                    isPlaying: playbackManager.isPlaying
                )
                .equatable()
                .frame(height: 10)
                .frame(maxWidth: Self.trackWidth)
            } else {
                progressSlider
            }

            ProgressTrailingSlot(
                accent: accent,
                isStream: isStream,
                isPlaying: playbackManager.isPlaying,
                isBuffering: playbackManager.isBuffering,
                duration: playbackManager.currentTrack?.duration ?? 0,
                slotWidth: Self.sideSlotWidth,
                font: .system(size: 11, weight: .medium)
            )
        }
        .onChange(of: playbackManager.currentTrack?.id) {
            isDraggingProgress = false
            tempProgressValue = 0
        }
    }

    private var progressSlider: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(
                        width: geometry.size.width * progressPercentage,
                        height: 4
                    )
                    .animation(isDraggingProgress ? .none : .easeInOut(duration: 0.2), value: progressPercentage)

                Circle()
                    .fill(accent)
                    .frame(width: 12, height: 12)
                    .opacity(isDraggingProgress || hoveredOverProgress ? 1.0 : 0.0)
                    .offset(x: (geometry.size.width * progressPercentage) - 6)
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
        .frame(height: 10)
        .frame(maxWidth: Self.trackWidth)
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
        let percentage = x / width
        let duration = HelperUtils.sanitizedDuration(playbackManager.currentTrack?.duration ?? 0)
        let newTime = percentage * duration
        playbackManager.seekTo(time: newTime)
    }
}
