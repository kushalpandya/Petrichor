import SwiftUI

struct TrackGridView: View {
    let tracks: [Track]
    let onPlayTrack: (Track) -> Void
    let contextMenuItems: (Track) -> [ContextMenuItem]

    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var hoveredTrackID: UUID?
    @State private var isScrolling = false
    @State private var scrollWorkItem: DispatchWorkItem?

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]

    var body: some View {
        scrollViewContent
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { _ in
                handleScrollChange()
            }
    }

    private var scrollViewContent: some View {
        ScrollView {
            gridContent
                .background(scrollDetector)
        }
    }

    private var gridContent: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { _, track in
                gridItem(for: track)
            }
        }
        .padding()
    }

    private func gridItem(for track: Track) -> some View {
        TrackGridItem(
            track: track
        ) {
            let isCurrentTrack = playbackManager.currentTrack?.url.path == track.url.path
            if !isCurrentTrack {
                onPlayTrack(track)
            }
        }
        .contextMenu {
            TrackContextMenuContent(items: contextMenuItems(track))
        }
        .id(track.id)
        .allowsHitTesting(!isScrolling)
    }

    private var scrollDetector: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: geometry.frame(in: .named("scroll")).origin.y
            )
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

// MARK: - Track Grid Item (Optimized)
private struct TrackGridItem: View {
    let track: Track
    let onPlay: () -> Void

    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var isHovered = false
    @State private var artworkImage: NSImage?

    private var isCurrentTrack: Bool {
        guard let currentTrack = playbackManager.currentTrack else { return false }
        return currentTrack.url.path == track.url.path
    }

    private var isPlaying: Bool {
        isCurrentTrack && playbackManager.isPlaying
    }

    var body: some View {
        VStack(spacing: 8) {
            artworkSection
            trackInfoSection
        }
        .padding(8)
        .background(backgroundView)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) {
            onPlay()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .task(id: track.id) {
            await loadTrackArtworkAsync(
                from: track.albumArtworkLarge,
                into: $artworkImage,
                delay: TimeConstants.oneHundredMilliseconds
            )
        }
        .onDisappear { artworkImage = nil }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var artworkSection: some View {
        ZStack {
            artworkView
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(isHovered || isCurrentTrack ? 0.4 : 0))
            
            Button(action: {
                if isCurrentTrack {
                    playbackManager.togglePlayPause()
                } else {
                    onPlay()
                }
            }) {
                Image(systemName: isPlaying ? Icons.pauseFill : Icons.playFill)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .buttonStyle(.borderless)
            .opacity(isHovered || isCurrentTrack ? 1 : 0)
            .allowsHitTesting(isHovered || isCurrentTrack)
            
            if isCurrentTrack && isPlaying {
                VStack {
                    HStack {
                        Spacer()
                        PlayingIndicator()
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 160, height: 160)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artworkImage = artworkImage {
            Image(nsImage: artworkImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Image(systemName: Icons.musicNote)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                )
        }
    }

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(.system(size: 14, weight: isCurrentTrack ? .medium : .regular))
                .foregroundColor(isCurrentTrack ? .accentColor : .primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(track.title)

            Text(track.artist)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .help(track.artist)

            if !track.album.isEmpty && track.album != "Unknown Album" {
                Text(track.album)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .help(track.album)
            }
        }
        .frame(width: 160, alignment: .leading)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                isPlaying ?
                (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.08) : Color.clear) :
                (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
