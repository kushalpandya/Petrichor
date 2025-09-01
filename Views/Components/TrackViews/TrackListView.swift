import SwiftUI

struct TrackListView: View {
    let tracks: [Track]
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: (Track) -> [ContextMenuItem]

    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var hoveredTrackID: UUID?
    @State private var isScrolling = false
    @State private var scrollWorkItem: DispatchWorkItem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(tracks, id: \.id) { track in
                    TrackListRow(
                        track: track,
                        isHovered: isScrolling ? false : (hoveredTrackID == track.id),
                        isScrolling: isScrolling,
                        onPlay: {
                            let isCurrentTrack = playbackManager.currentTrack?.url.path == track.url.path
                            if !isCurrentTrack {
                                onPlayTrack(track)
                            }
                        },
                        onHover: { isHovered in
                            if !isScrolling {
                                hoveredTrackID = isHovered ? track.id : nil
                            }
                        }
                    )
                    .contextMenu {
                        TrackContextMenuContent(items: contextMenuItems(track))
                    }
                    .id(track.id)
                }
            }
            .padding(5)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: geometry.frame(in: .named("scroll")).origin.y
                    )
                }
            )
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { _ in
            handleScrollChange()
        }
    }
    
    private func handleScrollChange() {
        isScrolling = true
        hoveredTrackID = nil
        
        scrollWorkItem?.cancel()
        
        scrollWorkItem = DispatchWorkItem {
            isScrolling = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: scrollWorkItem!)
    }
}

// MARK: - Track List Row
private struct TrackListRow: View {
    let track: Track
    let isHovered: Bool
    let isScrolling: Bool
    let onPlay: () -> Void
    let onHover: (Bool) -> Void

    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var artworkImage: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            playButtonSection
            trackContent
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: onPlay)
        }
        .frame(height: 60)
        .background(backgroundView)
        .onHover(perform: onHover)
    }

    // MARK: - Computed Properties

    private var isCurrentTrack: Bool {
        guard let currentTrack = playbackManager.currentTrack else { return false }
        return currentTrack.url.path == track.url.path
    }

    private var isPlaying: Bool {
        isCurrentTrack && playbackManager.isPlaying
    }

    // MARK: - View Components

    private var playButtonSection: some View {
        ZStack {
            if shouldShowPlayButton {
                Button(action: handlePlayButtonTap) {
                    Image(systemName: playButtonIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else if isPlaying && !isHovered {
                PlayingIndicator()
                    .frame(width: 16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
        .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: shouldShowPlayButton)
    }

    private var trackContent: some View {
        HStack(spacing: 12) {
            albumArtwork
            trackInfo
            Spacer()
            durationLabel
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var albumArtwork: some View {
        Group {
            if let artworkImage = artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if track.isMetadataLoaded {
                placeholderArtwork
            } else {
                loadingArtwork
            }
        }
        .task(id: track.id) {
            guard artworkImage == nil else { return }
            
            let delay = isScrolling ? TimeConstants.oneFiftyMilliseconds : TimeConstants.fiftyMilliseconds
            
            await loadTrackArtworkAsync(
                from: track.albumArtworkMedium,
                into: $artworkImage,
                delay: delay
            )
        }
        .onDisappear {
            artworkImage = nil
        }
    }

    private var placeholderArtwork: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.2))
            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
            .overlay(
                Image(systemName: Icons.musicNote)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            )
    }

    private var loadingArtwork: some View {
        ProgressView()
            .scaleEffect(0.5)
            .frame(width: ViewDefaults.listArtworkSize, height: ViewDefaults.listArtworkSize)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            titleLabel
            detailsLabel
        }
    }

    private var titleLabel: some View {
        Text(track.title)
            .font(.system(size: 14, weight: isCurrentTrack ? .medium : .regular))
            .foregroundColor(isCurrentTrack ? .accentColor : .primary)
            .lineLimit(1)
            .redacted(reason: track.isMetadataLoaded ? [] : .placeholder)
    }

    private var detailsLabel: some View {
        HStack(spacing: 4) {
            Text(track.artist)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .redacted(reason: track.isMetadataLoaded ? [] : .placeholder)

            if shouldShowAlbum {
                Text("•")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(track.album)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .redacted(reason: track.isMetadataLoaded ? [] : .placeholder)
            }

            if shouldShowYear {
                Text("•")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text(track.year)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var durationLabel: some View {
        Text(formatDuration(track.duration))
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .monospacedDigit()
            .redacted(reason: track.isMetadataLoaded ? [] : .placeholder)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
            .animation(.easeInOut(duration: AnimationDuration.quickDuration), value: isHovered)
    }

    // MARK: - Helper Properties

    private var shouldShowPlayButton: Bool {
        // Show button if:
        // 1. Hovered (play or pause depending on state)
        // 2. Current track but paused (persistent play button)
        isHovered || (isCurrentTrack && !playbackManager.isPlaying)
    }

    private var playButtonIcon: String {
        if isCurrentTrack {
            return isPlaying ? Icons.pauseFill : Icons.playFill
        }
        return Icons.playFill
    }

    private var backgroundColor: Color {
        if isPlaying {
            return isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.08) : Color.clear
        } else if isHovered {
            return Color(NSColor.selectedContentBackgroundColor).opacity(0.15)
        } else {
            return Color.clear
        }
    }

    private var shouldShowAlbum: Bool {
        !track.album.isEmpty && track.album != "Unknown Album"
    }

    private var shouldShowYear: Bool {
        track.isMetadataLoaded && !track.year.isEmpty && track.year != "Unknown Year"
    }

    // MARK: - Methods

    private func handlePlayButtonTap() {
        if isCurrentTrack {
            playbackManager.togglePlayPause()
        } else {
            onPlay()
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }
}

// MARK: - Supporting Types

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
