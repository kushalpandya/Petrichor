import SwiftUI
import Foundation

/// How the artwork-derived gradient behind the main player bar is drawn. Only takes
/// effect while "Tint interface with album artwork colors" is enabled.
enum PlayerBarBackgroundStyle: String, CaseIterable {
    case behindArtwork = "Behind album art"
    case fullWidth = "Full width"

    var displayName: String {
        switch self {
        case .behindArtwork: return String(localized: "Behind album art")
        case .fullWidth: return String(localized: "Full width")
        }
    }
}

/// Artwork-tinted backdrop for the main player bar. Kept separate (and Equatable) so
/// it only re-renders when the colors or style actually change, not on the play/pause
/// and progress-time updates that re-render the surrounding PlayerView body.
private struct PlayerBarBackground: View, Equatable {
    let colors: [Color]
    let style: PlayerBarBackgroundStyle

    var body: some View {
        if !colors.isEmpty {
            GeometryReader { geometry in
                if style == .fullWidth {
                    // Spread the artwork colors across the whole bar as a soft wash
                    // (mesh on macOS 15+, radial fallback below).
                    GradientBackground(colors: colors)
                } else {
                    RadialGradient(
                        colors: colors + [.clear],
                        center: .leading,
                        startRadius: 0,
                        endRadius: geometry.size.width * 0.25
                    )
                    .overlay(FocusStableMaterial())
                }
            }
            .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: colors)
        }
    }
}

/// The player bar's seek bar (time labels + slider), extracted so it alone carries the
/// `playbackProgressState` subscription. That keeps the ~10Hz progress ticks from
/// re-rendering the whole player bar during playback, matching NowPlayingProgressBar.
private struct PlayerProgressBar: View {
    /// Fill color for the progress track / handle (the resolved control color).
    let accent: Color

    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playbackProgressState: PlaybackProgressState

    @State private var isDraggingProgress = false
    @State private var tempProgressValue: Double = 0
    @State private var hoveredOverProgress = false

    var body: some View {
        HStack(spacing: 8) {
            // Current time
            Text(HelperUtils.formattedDuration(isDraggingProgress ? tempProgressValue : playbackProgressState.currentTime))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: timeLabelWidth, alignment: .trailing)

            // Progress slider
            progressSlider

            // Total duration
            Text(HelperUtils.formattedDuration(playbackManager.currentTrack?.duration ?? 0))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: timeLabelWidth, alignment: .leading)
        }
        .onChange(of: playbackManager.currentTrack?.id) {
            isDraggingProgress = false
            tempProgressValue = 0
        }
    }

    /// Widens the time labels when the current track is an hour or longer so the
    /// `H:MM:SS` form isn't clipped; otherwise keeps the compact `M:SS` width.
    private var timeLabelWidth: CGFloat {
        (playbackManager.currentTrack?.duration ?? 0) >= 3600 ? 56 : 40
    }

    private var progressSlider: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    // Progress track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(
                            width: geometry.size.width * progressPercentage,
                            height: 4
                        )
                        .animation(isDraggingProgress ? .none : .easeInOut(duration: 0.2), value: progressPercentage)

                    // Drag handle
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
        }
        .frame(height: 10)
        .frame(maxWidth: 400)
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
                // Reset dragging state after seek completes
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

struct PlayerView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var rightSidebarContent: RightSidebarContent
    
    @Environment(\.scenePhase)
    var scenePhase
    @Environment(\.colorScheme)
    var colorScheme

    @AppStorage("useArtworkColors")
    private var useArtworkColors = true

    @AppStorage("showTrackTechnicalInfo")
    private var showTrackTechnicalInfo = true

    @AppStorage("tintPlaybackControls")
    private var tintPlaybackControls = true

    @AppStorage("playerBarBackgroundStyle")
    private var playerBarBackgroundStyle: PlayerBarBackgroundStyle = .fullWidth

    @State private var gradientColors: [Color] = []
    @State private var currentTrackId: UUID?
    @State private var cachedArtworkImage: NSImage?
    @State private var playButtonPressed = false
    @State private var isMuted = false
    @State private var previousVolume: Float = 0.7
    @State private var isDraggingVolume = false

    var body: some View {
        ZStack {
            // Artwork-tinted backdrop, isolated into its own equatable view so the
            // frequent play/pause and progress-time re-renders of this body don't
            // re-evaluate (and visibly flash) the gradient and material.
            PlayerBarBackground(colors: gradientColors, style: playerBarBackgroundStyle)
                .equatable()

            // Content layer
            HStack(spacing: 20) {
                // Left section: Album art and track info
                leftSection

                Spacer()

                // Center section: Playback controls and progress
                centerSection

                Spacer()

                // Right section: Volume and queue controls
                rightSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            setupInitialState()
        }
        .onChange(of: playbackManager.currentTrack?.id) {
            updateGradientColors()
        }
        .onChange(of: colorScheme) {
            updateGradientColors()
        }
        .onChange(of: useArtworkColors) {
            updateGradientColors()
        }
    }

    // MARK: - View Sections

    private var leftSection: some View {
        HStack(spacing: 16) {
            albumArtwork
            trackDetails
        }
        .frame(width: 320, alignment: .leading)
    }

    private var centerSection: some View {
        VStack(spacing: 8) {
            playbackControls
            PlayerProgressBar(accent: controlAccent)
        }
        .frame(maxWidth: 500)
    }

    private var rightSection: some View {
        HStack(spacing: 12) {
            lyricsButton
            volumeControl
            queueButton
            miniPlayerButton
            immersiveButton
        }
        .frame(width: 320, alignment: .trailing)
    }

    // MARK: - Left Section Components

    private var albumArtwork: some View {
        let trackArtworkInfo = playbackManager.currentTrack.map { track in
            TrackArtworkInfo(id: track.id, artworkData: track.artworkData)
        }

        return PlayerAlbumArtView(
            trackInfo: trackArtworkInfo,
            contextMenuItems: currentTrackContextMenuItems
        ) {
            if let currentTrack = playbackManager.currentTrack {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowTrackInfo"),
                    object: nil,
                    userInfo: ["track": currentTrack]
                )
            }
        }
        .equatable()
    }

    private var trackDetails: some View {
        PlayerTrackDetailsView(
            track: playbackManager.currentTrack,
            contextMenuItems: currentTrackContextMenuItems,
            playlistManager: playlistManager,
            showTechnicalInfo: showTrackTechnicalInfo
        )
        .equatable()
    }

    // MARK: - Center Section Components

    private var playbackControls: some View {
        HStack(spacing: 12) {
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
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(playlistManager.isShuffleEnabled ? controlAccent : Color.secondary)
                .frame(width: 32, height: 32)
                .activeControlIndicator(isActive: playlistManager.isShuffleEnabled, color: controlAccent)
        })
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(playbackManager.currentTrack == nil)
        .help(playlistManager.isShuffleEnabled ? String(localized: "Disable Shuffle") : String(localized: "Enable Shuffle"))
    }

    private var previousButton: some View {
        Button(action: {
            playlistManager.playPreviousTrack()
        }, label: {
            Image(systemName: Icons.backwardFill)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(controlsTinted ? controlAccent : .primary)
                .frame(width: 32, height: 32)
        })
        .buttonStyle(ControlButtonStyle())
        .tint(controlsTinted ? controlAccent : .primary)
        .hoverEffect(scale: 1.1)
        .disabled(playbackManager.currentTrack == nil)
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
                        .fill(controlTint)
                        .shadow(color: controlTint.opacity(0.3), radius: 6, x: 0, y: 3)
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
        .disabled(playbackManager.currentTrack == nil)
        .help(playbackManager.isPlaying ? String(localized: "Pause") : String(localized: "Play"))
        .id("playPause")
    }

    private var nextButton: some View {
        Button(action: {
            playlistManager.playNextTrack()
        }, label: {
            Image(systemName: Icons.forwardFill)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(controlsTinted ? controlAccent : .primary)
                .frame(width: 32, height: 32)
        })
        .buttonStyle(ControlButtonStyle())
        .tint(controlsTinted ? controlAccent : .primary)
        .hoverEffect(scale: 1.1)
        .help("Next")
        .disabled(playbackManager.currentTrack == nil)
    }

    private var repeatButton: some View {
        Button(action: {
            playlistManager.toggleRepeatMode()
        }, label: {
            Image(systemName: Icons.repeatIcon(for: playlistManager.repeatMode))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(playlistManager.repeatMode != .off ? controlAccent : Color.secondary)
                .frame(width: 32, height: 32)
                .activeControlIndicator(isActive: playlistManager.repeatMode != .off, color: controlAccent)
        })
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .help(playlistManager.repeatMode.tooltip)
        .disabled(playbackManager.currentTrack == nil)
    }

    // MARK: - Right Section Components

    private var volumeControl: some View {
        HStack(spacing: 8) {
            volumeButton
            volumeSlider
        }
    }

    private var volumeButton: some View {
        Button(action: toggleMute) {
            Image(systemName: volumeIcon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.1)
        .help(isMuted ? String(localized: "Unmute") : String(localized: "Mute"))
    }

    private var volumeSlider: some View {
        Slider(
            value: Binding(
                get: { playbackManager.volume },
                set: { newVolume in
                    // Save previous volume before changing
                    if playbackManager.volume > 0.01 {
                        previousVolume = playbackManager.volume
                    }
                    
                    playbackManager.setVolume(newVolume)
                    
                    // Update mute state
                    if newVolume < 0.01 {
                        isMuted = true
                    } else if isMuted {
                        isMuted = false
                    }
                }
            ),
            in: 0...1
        ) { editing in
                isDraggingVolume = editing
        }
        .frame(width: 100)
        .controlSize(.small)
        .tint(controlAccent)
        .overlay(alignment: .leading) {
            if isDraggingVolume {
                Text(playbackManager.volume.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(radius: 2)
                    )
                    .offset(x: 100 * CGFloat(playbackManager.volume) - 15, y: -25)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.1), value: playbackManager.volume)
            }
        }
    }

    private var queueButton: some View {
        Button(action: {
            rightSidebarContent = rightSidebarContent == .queue ? .none : .queue
        }, label: {
            Image(systemName: Icons.queueList)
                .font(.system(size: 16))
                .foregroundColor(rightSidebarContent == .queue ? .white : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(rightSidebarContent == .queue ? controlTint : Color.secondary.opacity(0.1))
                )
        })
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(scale: 1.1)
        .help(rightSidebarContent == .queue ? String(localized: "Hide Queue") : String(localized: "Show Queue"))
    }
    
    private var immersiveButton: some View {
        Button(action: {
            // Routed through ContentView to centralize the open animation + toolbar handling.
            NotificationCenter.default.post(name: .toggleImmersivePlayer, object: nil)
        }, label: {
            Image(systemName: Icons.immersive)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                )
        })
        .buttonStyle(PlainButtonStyle())
        .disabled(!hasCurrentTrack)
        .opacity(hasCurrentTrack ? 1.0 : 0.5)
        .hoverEffect(scale: hasCurrentTrack ? 1.1 : 1.0)
        .help("Open Immersive Mode")
    }

    private var miniPlayerButton: some View {
        Button(action: {
            MiniPlayerWindowManager.shared.show()
        }, label: {
            Image(systemName: Icons.miniPlayer)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                )
        })
        .buttonStyle(PlainButtonStyle())
        .disabled(!hasCurrentTrack)
        .opacity(hasCurrentTrack ? 1.0 : 0.5)
        .hoverEffect(scale: hasCurrentTrack ? 1.1 : 1.0)
        .help("Open Mini Player")
    }

    private var lyricsButton: some View {
        Button(action: {
            rightSidebarContent = rightSidebarContent == .lyrics ? .none : .lyrics
        }, label: {
            Image(Icons.customLyrics)
                .foregroundColor(rightSidebarContent == .lyrics ? .white : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(rightSidebarContent == .lyrics ? controlTint : Color.secondary.opacity(0.1))
                )
        })
        .buttonStyle(PlainButtonStyle())
        .disabled(!hasCurrentTrack)
        .opacity(hasCurrentTrack ? 1.0 : 0.5)
        .hoverEffect(scale: hasCurrentTrack ? 1.1 : 1.0)
        .help(rightSidebarContent == .lyrics ? String(localized: "Hide Lyrics") : String(localized: "Show Lyrics"))
    }

    // MARK: - Computed Properties
    
    private var hasCurrentTrack: Bool {
        playbackManager.currentTrack != nil
    }

    private var controlsTinted: Bool {
        useArtworkColors && tintPlaybackControls
    }

    /// Raw dominant color used to fill the play/pause button (shared with the mini
    /// player and immersive mode via `NowPlayingArtwork`), or the accent color when
    /// tinting is disabled.
    private var controlTint: Color {
        NowPlayingArtwork.tint(for: playbackManager.currentTrack, useArtworkTint: controlsTinted)
    }

    /// Legible, mode-adjusted dominant color for the secondary controls (shuffle/
    /// repeat active, prev/next, progress, and volume), or the accent color when
    /// tinting is disabled.
    private var controlAccent: Color {
        NowPlayingArtwork.controlColor(for: playbackManager.currentTrack, useArtworkTint: controlsTinted, isDarkBackground: colorScheme == .dark)
    }

    private var volumeIcon: String {
        if isMuted || playbackManager.volume < 0.01 {
            return "speaker.slash.fill"
        } else if playbackManager.volume < 0.33 {
            return "speaker.fill"
        } else if playbackManager.volume < 0.66 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    private var currentTrackContextMenuItems: [ContextMenuItem] {
        guard let track = playbackManager.currentTrack else { return [] }
        
        return TrackContextMenu.createPlayerViewMenuItems(
            for: track,
            playlistManager: playlistManager
        )
    }

    // MARK: - Helper Methods

    private func setupInitialState() {
        // Initialize the cached album art
        if let artworkData = playbackManager.currentTrack?.artworkData,
           let image = NSImage(data: artworkData) {
            cachedArtworkImage = image
            currentTrackId = playbackManager.currentTrack?.id
        }

        if playbackManager.volume < 0.01 {
            isMuted = true
            previousVolume = 0.7
        } else {
            previousVolume = playbackManager.volume
        }

        updateGradientColors()
    }

    private func updateGradientColors() {
        guard useArtworkColors,
              let track = playbackManager.currentTrack,
              !track.dominantColors.isEmpty else {
            gradientColors = []
            return
        }

        gradientColors = track.backgroundGradientColors(isDark: colorScheme == .dark)
    }

    private func toggleMute() {
        if isMuted {
            // Unmute - restore previous volume
            playbackManager.setVolume(previousVolume)
            isMuted = false
        } else {
            // Mute - save current volume and set to 0
            previousVolume = playbackManager.volume
            playbackManager.setVolume(0)
            isMuted = true
        }
    }
}

// MARK: - Album Art

struct PlayerTrackDetailsView: View, Equatable {
    let track: Track?
    let contextMenuItems: [ContextMenuItem]
    let playlistManager: PlaylistManager
    let showTechnicalInfo: Bool

    static func == (lhs: PlayerTrackDetailsView, rhs: PlayerTrackDetailsView) -> Bool {
        lhs.track?.id == rhs.track?.id &&
        lhs.track?.isFavorite == rhs.track?.isFavorite &&
        lhs.showTechnicalInfo == rhs.showTechnicalInfo
    }

    // When the format badges are hidden, the remaining three rows grow slightly
    // and spread out so they stay vertically balanced against the album artwork.
    private var titleFontSize: CGFloat { showTechnicalInfo ? 14 : 16 }
    private var artistFontSize: CGFloat { showTechnicalInfo ? 12 : 14 }
    private var albumFontSize: CGFloat { showTechnicalInfo ? 11 : 13 }
    private var rowSpacing: CGFloat { showTechnicalInfo ? 4 : 10 }
    private var titleRowHeight: CGFloat { showTechnicalInfo ? 16 : 20 }
    private var textRowHeight: CGFloat { showTechnicalInfo ? 15 : 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            // Title row with favorite button
            HStack(alignment: .center, spacing: 8) {
                Text(track?.title ?? "")
                    .font(.system(size: titleFontSize, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .truncationMode(.tail)
                    .help(track?.title ?? "")
                    .contextMenu {
                        TrackContextMenuContent(items: contextMenuItems)
                    }

                if let track = track {
                    FavoriteButtonView(
                        trackId: track.id,
                        isFavorite: track.isFavorite
                    ) { playlistManager.toggleFavorite(for: track) }
                }
            }
            .frame(height: titleRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Artist with marquee
            MarqueeText(
                text: track?.displayArtist ?? "",
                font: .system(size: artistFontSize),
                color: .secondary
            )
            .frame(height: textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                TrackContextMenuContent(items: contextMenuItems)
            }

            // Album with marquee
            MarqueeText(
                text: track?.displayAlbum ?? "",
                font: .system(size: albumFontSize),
                color: .secondary
            )
            .frame(height: textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                TrackContextMenuContent(items: contextMenuItems)
            }

            if showTechnicalInfo {
                formatBadgeRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formatBadgeRow: some View {
        HStack(spacing: 4) {
            if let track = track {
                if track.isLossless {
                    LosslessLabel(iconSize: 12, font: .system(size: 10), spacing: 3)
                }
                if let codec = track.codecDisplay {
                    FormatBadge(text: codec)
                }
                // No need to show Bitrate for Lossless tracks, as it is pointless
                if !track.isLossless, let bitrate = track.bitrateDisplay {
                    FormatBadge(text: bitrate)
                }
                if let sampleRate = track.sampleRateDisplay {
                    FormatBadge(text: sampleRate)
                }
                if let channels = track.channelsDisplay {
                    FormatBadge(text: channels)
                }
            }
        }
        .frame(height: 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Format Badge

private struct FormatBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
            )
    }
}

struct FavoriteButtonView: View, Equatable {
    let trackId: UUID
    let isFavorite: Bool
    let onToggle: () -> Void

    static func == (lhs: FavoriteButtonView, rhs: FavoriteButtonView) -> Bool {
        lhs.trackId == rhs.trackId &&
        lhs.isFavorite == rhs.isFavorite
    }

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: isFavorite ? Icons.starFill : Icons.star)
                .font(.system(size: 12))
                .foregroundColor(isFavorite ? .yellow : .secondary)
                .animation(.easeInOut(duration: 0.2), value: isFavorite)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hoverEffect(scale: 1.15)
        .help(isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"))
    }
}

struct TrackArtworkInfo: Equatable {
    let id: UUID
    let artworkData: Data?

    static func == (lhs: TrackArtworkInfo, rhs: TrackArtworkInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct PlayerAlbumArtView: View, Equatable {
    let trackInfo: TrackArtworkInfo?
    let contextMenuItems: [ContextMenuItem]
    let onTap: (() -> Void)?

    static func == (lhs: PlayerAlbumArtView, rhs: PlayerAlbumArtView) -> Bool {
        lhs.trackInfo == rhs.trackInfo
    }

    var body: some View {
        AlbumArtworkImage(trackInfo: trackInfo)
            .onTapGesture {
                onTap?()
            }
            .contextMenu {
                TrackContextMenuContent(items: contextMenuItems)
            }
    }
}

private struct AlbumArtworkImage: View {
    let trackInfo: TrackArtworkInfo?
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Static image content
            AlbumArtworkContent(trackInfo: trackInfo)
        }
        .frame(width: 76, height: 76)
        .shadow(
            color: .black.opacity(isHovered ? 0.4 : 0.2),
            radius: isHovered ? 6 : 2,
            x: 0,
            y: isHovered ? 3 : 1
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct AlbumArtworkContent: View {
    let trackInfo: TrackArtworkInfo?

    var body: some View {
        if let artworkData = trackInfo?.artworkData,
           let nsImage = NSImage(data: artworkData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.15))
                .overlay(
                    Image(systemName: Icons.musicNote)
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.secondary)
                )
        }
    }
}

// MARK: - Custom Button Style

struct ControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var rightSidebarContent: RightSidebarContent = .none

        var body: some View {
            let coordinator = AppCoordinator()
            PlayerView(
                rightSidebarContent: $rightSidebarContent
            )
            .environmentObject(coordinator.playbackManager)
            .environmentObject(coordinator.playlistManager)
            .environmentObject(coordinator.playbackManager.playbackProgressState)
            .frame(height: 200)
        }
    }

    return PreviewWrapper()
}
