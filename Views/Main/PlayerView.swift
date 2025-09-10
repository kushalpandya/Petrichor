import SwiftUI
import Foundation

struct PlayerView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @Binding var showingQueue: Bool
    
    @Environment(\.scenePhase)
    var scenePhase

    @State private var isDraggingProgress = false
    @State private var tempProgressValue: Double = 0
    @State private var currentTrackId: UUID?
    @State private var cachedArtworkImage: NSImage?
    @State private var hoveredOverProgress = false
    @State private var playButtonPressed = false
    @State private var isMuted = false
    @State private var previousVolume: Float = 0.7
    
    // UI Timer state
    @State private var displayTime: Double = 0
    @State private var uiTimer: Timer?
    @State private var playbackStartTime: Date?
    @State private var playbackStartOffset: Double = 0

    var body: some View {
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
        .frame(maxWidth: .infinity)
        .onAppear {
            setupInitialState()
            syncDisplayTime()
        }
        .onChange(of: playbackManager.isPlaying) { _, isPlaying in
            // Only start timer if scene is active
            if isPlaying && scenePhase == .active {
                startUITimer()
            } else {
                stopUITimer()
            }
        }
        .onChange(of: playbackManager.currentTrack) { _, _ in
            syncDisplayTime()
            // Only start timer if scene is active
            if playbackManager.isPlaying && scenePhase == .active {
                startUITimer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PlayerDidSeek"))) { notification in
            if let time = notification.userInfo?["time"] as? Double {
                displayTime = time
                playbackStartTime = Date()
                playbackStartOffset = time
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                // Window is visible and active
                if playbackManager.isPlaying {
                    syncDisplayTime() // Sync time when becoming active
                    startUITimer()
                }
            case .inactive, .background:
                // Window is minimized, hidden, or app is in background
                stopUITimer()
            @unknown default:
                break
            }
        }
        .onChange(of: playbackManager.volume) { oldValue, newValue in
            if oldValue < 0.01 && newValue > 0.01 {
                isMuted = false
            } else if newValue < 0.01 {
                isMuted = true
                previousVolume = oldValue > 0.01 ? oldValue : 0.7
            }
        }
    }
    
    // MARK: - UI Timer Management
    
    private func startUITimer() {
        guard scenePhase == .active else { return }

        stopUITimer()
        
        // Capture the current playback position
        playbackStartTime = Date()
        playbackStartOffset = playbackManager.actualCurrentTime
        displayTime = playbackStartOffset
        
        // Create a timer that updates the UI every second
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateDisplayTime()
        }
        uiTimer?.tolerance = 0.1
    }
    
    private func stopUITimer() {
        uiTimer?.invalidate()
        uiTimer = nil
        syncDisplayTime()
    }
    
    private func updateDisplayTime() {
        guard let startTime = playbackStartTime,
              playbackManager.isPlaying,
              !isDraggingProgress else { return }
        
        // Calculate elapsed time since playback started
        let elapsed = Date().timeIntervalSince(startTime)
        let newTime = playbackStartOffset + elapsed
        
        // Clamp to track duration
        if let duration = playbackManager.currentTrack?.duration {
            displayTime = min(newTime, duration)
        } else {
            displayTime = newTime
        }
    }
    
    private func syncDisplayTime() {
        displayTime = playbackManager.actualCurrentTime
    }

    // MARK: - View Sections

    private var leftSection: some View {
        HStack(spacing: 16) {
            albumArtwork
            trackDetails
        }
        .frame(width: 250, alignment: .leading)
    }

    private var centerSection: some View {
        VStack(spacing: 8) {
            playbackControls
            progressBar
        }
        .frame(maxWidth: 500)
    }

    private var rightSection: some View {
        HStack(spacing: 12) {
            volumeControl
            queueButton
        }
        .frame(width: 250, alignment: .trailing)
    }

    // MARK: - Left Section Components

    private var albumArtwork: some View {
        let trackArtworkInfo = playbackManager.currentTrack.map { track in
            TrackArtworkInfo(id: track.id, artworkData: track.artworkData)
        }

        return PlayerAlbumArtView(trackInfo: trackArtworkInfo) {
            if let currentTrack = playbackManager.currentTrack {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowTrackInfo"),
                    object: nil,
                    userInfo: ["track": currentTrack]
                )
            }
        }
        .equatable()
        .contextMenu {
            TrackContextMenuContent(items: currentTrackContextMenuItems)
        }
    }

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with favorite button
            HStack(alignment: .center, spacing: 8) {
                Text(playbackManager.currentTrack?.title ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .truncationMode(.tail)
                    .help(playbackManager.currentTrack?.title ?? "")
                    .contextMenu {
                        TrackContextMenuContent(items: currentTrackContextMenuItems)
                    }

                favoriteButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Artist with marquee
            MarqueeText(
                text: playbackManager.currentTrack?.artist ?? "",
                font: .system(size: 12),
                color: .secondary
            )
            .frame(height: 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                TrackContextMenuContent(items: currentTrackContextMenuItems)
            }

            // Album with marquee
            MarqueeText(
                text: playbackManager.currentTrack?.album ?? "",
                font: .system(size: 11),
                color: .secondary
            )
            .frame(height: 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                TrackContextMenuContent(items: currentTrackContextMenuItems)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favoriteButton: some View {
        Group {
            if let track = playbackManager.currentTrack {
                Button(action: {
                    playlistManager.toggleFavorite(for: track)
                }) {
                    Image(systemName: track.isFavorite ? Icons.starFill : Icons.star)
                        .font(.system(size: 12))
                        .foregroundColor(track.isFavorite ? .yellow : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: track.isFavorite)
                }
                .buttonStyle(.plain)
                .hoverEffect(scale: 1.15)
                .help(track.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
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
        }) {
            Image(systemName: Icons.shuffleFill)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(playlistManager.isShuffleEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(playbackManager.currentTrack == nil)
        .help(playlistManager.isShuffleEnabled ? "Disable Shuffle" : "Enable Shuffle")
    }

    private var previousButton: some View {
        Button(action: {
            playlistManager.playPreviousTrack()
        }) {
            Image(systemName: Icons.backwardFill)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .disabled(playbackManager.currentTrack == nil)
        .help("Previous")
    }

    private var playPauseButton: some View {
        Button(action: {
            playbackManager.togglePlayPause()
        }) {
            PlayPauseIcon(isPlaying: playbackManager.isPlaying)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                )
        }
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
        .help(playbackManager.isPlaying ? "Pause" : "Play")
        .id("playPause")
    }

    private var nextButton: some View {
        Button(action: {
            playlistManager.playNextTrack()
        }) {
            Image(systemName: Icons.forwardFill)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .help("Next")
        .disabled(playbackManager.currentTrack == nil)
    }

    private var repeatButton: some View {
        Button(action: {
            playlistManager.toggleRepeatMode()
        }) {
            Image(systemName: Icons.repeatIcon(for: playlistManager.repeatMode))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(playlistManager.repeatMode != .off ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(ControlButtonStyle())
        .hoverEffect(scale: 1.1)
        .help("Toggle repeat mode")
        .disabled(playbackManager.currentTrack == nil)
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            // Current time - updated to use displayTime
            Text(formatDuration(isDraggingProgress ? tempProgressValue : displayTime))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)

            // Progress slider
            progressSlider

            // Total duration
            Text(formatDuration(playbackManager.currentTrack?.duration ?? 0))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
        }
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
                        .fill(Color.accentColor)
                        .frame(
                            width: geometry.size.width * progressPercentage,
                            height: 4
                        )

                    // Drag handle
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 12, height: 12)
                        .opacity(isDraggingProgress || hoveredOverProgress ? 1.0 : 0.0)
                        .offset(x: (geometry.size.width * progressPercentage) - 6)
                        .animation(isDraggingProgress ? .none : .easeInOut(duration: 0.15), value: progressPercentage)
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
        .help(isMuted ? "Unmute" : "Mute")
    }

    private var volumeSlider: some View {
        Slider(
            value: Binding(
                get: { playbackManager.volume },
                set: { newVolume in
                    playbackManager.setVolume(newVolume)
                    // If user moves slider, unmute
                    if isMuted && newVolume > 0 {
                        isMuted = false
                    }
                }
            ),
            in: 0...1
        )
        .frame(width: 100)
        .controlSize(.small)
        .disabled(isMuted)
    }

    private var queueButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                showingQueue.toggle()
            }
        }) {
            Image(systemName: "list.bullet")
                .font(.system(size: 16))
                .foregroundColor(showingQueue ? .white : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(showingQueue ? Color.accentColor : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .hoverEffect(scale: 1.1)
        .help(showingQueue ? "Hide Queue" : "Show Queue")
    }

    // MARK: - Computed Properties

    private var progressPercentage: Double {
        guard let duration = playbackManager.currentTrack?.duration, duration > 0 else { return 0 }

        if isDraggingProgress {
            return min(1, max(0, tempProgressValue / duration))
        } else {
            return min(1, max(0, displayTime / duration))  // Updated to use displayTime
        }
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
        
        return TrackContextMenu.createMenuItems(
            for: track,
            playbackManager: playbackManager,
            playlistManager: playlistManager,
            currentContext: .library
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
    }

    private func progressDragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDraggingProgress {
                    isDraggingProgress = true
                }
                let percentage = max(0, min(1, value.location.x / geometry.size.width))
                tempProgressValue = percentage * (playbackManager.currentTrack?.duration ?? 0)
                displayTime = tempProgressValue  // Update displayTime while dragging
            }
            .onEnded { value in
                let percentage = max(0, min(1, value.location.x / geometry.size.width))
                let newTime = percentage * (playbackManager.currentTrack?.duration ?? 0)
                playbackManager.seekTo(time: newTime)
                // Reset dragging state after seek completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isDraggingProgress = false
                }
            }
    }

    private func handleProgressTap(at x: CGFloat, in width: CGFloat) {
        let percentage = x / width
        let newTime = percentage * (playbackManager.currentTrack?.duration ?? 0)
        playbackManager.seekTo(time: newTime)
        displayTime = newTime  // Update displayTime immediately
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
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

// Keep the existing supporting views and structs below...

// MARK: - Album Art

struct TrackArtworkInfo: Equatable {
    let id: UUID
    let artworkData: Data?

    static func == (lhs: TrackArtworkInfo, rhs: TrackArtworkInfo) -> Bool {
        lhs.id == rhs.id
    }
}

struct PlayerAlbumArtView: View, Equatable {
    let trackInfo: TrackArtworkInfo?
    let onTap: (() -> Void)?

    static func == (lhs: PlayerAlbumArtView, rhs: PlayerAlbumArtView) -> Bool {
        lhs.trackInfo == rhs.trackInfo
    }

    var body: some View {
        AlbumArtworkImage(trackInfo: trackInfo)
            .onTapGesture {
                onTap?()
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
        .frame(width: 56, height: 56)
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
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .overlay(
                    Image(systemName: Icons.musicNote)
                        .font(.system(size: 16, weight: .light))
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

private struct PlayPauseIcon: View {
    let isPlaying: Bool

    var body: some View {
        ZStack {
            Image(systemName: Icons.playFill)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .opacity(isPlaying ? 0 : 1)
                .scaleEffect(isPlaying ? 0.8 : 1)
                .rotationEffect(.degrees(isPlaying ? -90 : 0))

            Image(systemName: Icons.pauseFill)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .opacity(isPlaying ? 1 : 0)
                .scaleEffect(isPlaying ? 1 : 0.8)
                .rotationEffect(.degrees(isPlaying ? 0 : 90))
        }
        .animation(.easeInOut(duration: 0.2), value: isPlaying)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var showingQueue = false

        var body: some View {
            PlayerView(showingQueue: $showingQueue)
                .environmentObject({
                    let coordinator = AppCoordinator()
                    return coordinator.playbackManager
                }())
                .environmentObject({
                    let coordinator = AppCoordinator()
                    return coordinator.playlistManager
                }())
                .frame(height: 200)
        }
    }

    return PreviewWrapper()
}
