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
        GridItem(.adaptive(minimum: ViewDefaults.gridArtworkSize, maximum: 200), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(tracks, id: \.id) { track in
                    TrackGridItem(
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
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
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

// MARK: - Track Grid Item
private struct TrackGridItem: View {
    let track: Track
    let isHovered: Bool
    let isScrolling: Bool
    let onPlay: () -> Void
    let onHover: (Bool) -> Void

    @EnvironmentObject var playbackManager: PlaybackManager
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
        .onHover(perform: onHover)
        .animation(.easeInOut(duration: AnimationDuration.quickDuration), value: isHovered)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var artworkSection: some View {
        ZStack {
            artworkView
            
            if isHovered || isCurrentTrack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.4))
                
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
            }
            
            if isCurrentTrack && isPlaying {
                VStack {
                    HStack {
                        Spacer()
                        PlayingIndicator()
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
    }

    private var artworkView: some View {
        Group {
            if let artworkImage = artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: ViewDefaults.gridArtworkSize, height: ViewDefaults.gridArtworkSize)
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .task(id: track.id) {
            await loadArtwork()
        }
        .onDisappear {
            artworkImage = nil
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
        .frame(width: ViewDefaults.gridArtworkSize, alignment: .leading)
    }

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(
                isPlaying ?
                (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.08) : Color.clear) :
                (isHovered ? Color(NSColor.selectedContentBackgroundColor).opacity(0.15) : Color.clear)
            )
            .animation(.easeInOut(duration: AnimationDuration.quickDuration), value: isHovered)
    }
    
    private func loadArtwork() async {
        guard artworkImage == nil else { return }
        
        let delay = isScrolling ? TimeConstants.oneFiftyMilliseconds : TimeConstants.fiftyMilliseconds
        
        await loadTrackArtworkAsync(
            from: track.albumArtworkLarge,
            into: $artworkImage,
            delay: delay
        )
    }
}

// MARK: - Supporting Types

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
