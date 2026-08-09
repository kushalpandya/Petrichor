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
        .onChange(of: playbackManager.currentStation?.artworkCacheID) {
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

    /// Sized so the progress bar keeps its full width; narrower windows still compress
    /// it, but never state-by-state. See `PlayerProgressBar.preferredWidth`.
    private var centerSection: some View {
        VStack(spacing: 8) {
            playbackControls
            PlayerProgressBar(accent: controlAccent)
        }
        .frame(maxWidth: PlayerProgressBar.preferredWidth)
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

    @ViewBuilder private var albumArtwork: some View {
        if let station = playbackManager.currentStation {
            PlayerStationArtView(artworkID: station.artworkCacheID, artworkData: station.artworkData)
                .equatable()
        } else {
            let trackArtworkInfo = playbackManager.currentTrack.map { track in
                TrackArtworkInfo(id: track.id, artworkData: track.artworkData)
            }

            PlayerAlbumArtView(
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
    }

    @ViewBuilder private var trackDetails: some View {
        if let station = playbackManager.currentStation {
            PlayerStationDetailsView(
                stationName: station.name,
                nowPlaying: playbackManager.streamNowPlayingTitle,
                description: station.description,
                format: playbackManager.streamFormat,
                showTechnicalInfo: showTrackTechnicalInfo
            )
            .equatable()
        } else {
            PlayerTrackDetailsView(
                track: playbackManager.currentTrack,
                contextMenuItems: currentTrackContextMenuItems,
                playlistManager: playlistManager,
                showTechnicalInfo: showTrackTechnicalInfo
            )
            .equatable()
        }
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
        .opacity(transportDisabled ? ViewDefaults.disabledControlOpacity : 1)
        .disabled(transportDisabled)
        .help(playlistManager.isShuffleEnabled ? String(localized: "Disable Shuffle") : String(localized: "Enable Shuffle"))
    }

    private var transportDisabled: Bool {
        playbackManager.isTransportDisabled
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
        .opacity(transportDisabled ? ViewDefaults.disabledControlOpacity : 1)
        .disabled(transportDisabled)
        .help("Previous")
    }

    private var playPauseButton: some View {
        Button(action: {
            playbackManager.togglePlayPause()
        }, label: {
            PlayPauseIcon(
                isPlaying: playbackManager.isPlaying,
                stopInsteadOfPause: playbackManager.hasStation
            )
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
        .disabled(playbackManager.currentTrack == nil && playbackManager.currentStation == nil)
        .help(playbackManager.playPauseActionTitle)
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
        .opacity(transportDisabled ? ViewDefaults.disabledControlOpacity : 1)
        .disabled(transportDisabled)
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
        .opacity(transportDisabled ? ViewDefaults.disabledControlOpacity : 1)
        .disabled(transportDisabled)
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
        .tint(volumeAccent)
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
        .disabled(!playbackManager.hasPlayableContent)
        .opacity(playbackManager.hasPlayableContent ? 1.0 : 0.5)
        .hoverEffect(scale: playbackManager.hasPlayableContent ? 1.1 : 1.0)
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
        .disabled(!playbackManager.hasPlayableContent)
        .opacity(playbackManager.hasPlayableContent ? 1.0 : 0.5)
        .hoverEffect(scale: playbackManager.hasPlayableContent ? 1.1 : 1.0)
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

    /// `currentTrack` is nil for radio, so these key off "is anything loaded".
    private var controlsTinted: Bool {
        useArtworkColors && tintPlaybackControls
    }

    /// Raw dominant color used to fill the play/pause button (shared with the mini
    /// player and immersive mode via `NowPlayingArtwork`), or the accent color when
    /// tinting is disabled.
    private var controlTint: Color {
        NowPlayingArtwork.tint(for: playbackManager.nowPlayingSource, useArtworkTint: controlsTinted)
    }

    /// Legible, mode-adjusted dominant color for the secondary controls (shuffle/
    /// repeat active, prev/next, progress, and volume), or the accent color when
    /// tinting is disabled.
    private var controlAccent: Color {
        NowPlayingArtwork.controlColor(
            for: playbackManager.nowPlayingSource,
            useArtworkTint: controlsTinted,
            isDarkBackground: colorScheme == .dark
        )
    }

    private var volumeAccent: Color {
        playbackManager.nowPlayingSource == nil
            ? Color(nsColor: .controlAccentColor)
            : controlAccent
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
        if playbackManager.volume < 0.01 {
            isMuted = true
            previousVolume = 0.7
        } else {
            previousVolume = playbackManager.volume
        }

        updateGradientColors()
    }

    private func updateGradientColors() {
        gradientColors = NowPlayingArtwork.gradient(
            for: playbackManager.nowPlayingSource,
            isDark: colorScheme == .dark,
            enabled: useArtworkColors
        )
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

struct FormatBadge: View {
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
        AlbumArtworkImage(artworkData: trackInfo?.artworkData)
            .onTapGesture {
                onTap?()
            }
            .contextMenu {
                TrackContextMenuContent(items: contextMenuItems)
            }
    }
}

struct AlbumArtworkImage: View {
    let artworkData: Data?
    var placeholderIcon: String = Icons.musicNote
    /// No detail view behind a station, so no hover or click.
    var interactive: Bool = true

    @State private var isHovered = false

    private var hovering: Bool { interactive && isHovered }

    var body: some View {
        ZStack {
            // Static image content
            AlbumArtworkContent(artworkData: artworkData, placeholderIcon: placeholderIcon)
        }
        .frame(width: 76, height: 76)
        .shadow(
            color: .black.opacity(hovering ? 0.4 : 0.2),
            radius: hovering ? 6 : 2,
            x: 0,
            y: hovering ? 3 : 1
        )
        .scaleEffect(hovering ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: hovering)
        .contentShape(Rectangle())
        .onHover { newValue in
            guard interactive else { return }
            isHovered = newValue
        }
    }
}

struct AlbumArtworkContent: View {
    let artworkData: Data?
    let placeholderIcon: String

    var body: some View {
        if let artworkData,
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
                    Image(systemName: placeholderIcon)
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
