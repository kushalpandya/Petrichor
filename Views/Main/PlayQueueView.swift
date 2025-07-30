import SwiftUI
import UniformTypeIdentifiers

struct PlayQueueView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @State private var draggedTrack: Track?
    @State private var showingClearConfirmation = false
    @State private var hasAppeared = false
    @Binding var showingQueue: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            queueHeader

            Divider()

            // Queue content
            if playlistManager.currentQueue.isEmpty {
                emptyQueueView
            } else {
                queueListView
            }
        }
        .alert("Clear Queue", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                playlistManager.clearQueue()
            }
        } message: {
            Text("Are you sure you want to clear the entire queue? This will stop playback.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Delay animations until after the sidebar has slid in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                hasAppeared = true
            }
        }
        .onDisappear {
            hasAppeared = false
        }
    }

    // MARK: - Queue Header

    private var queueHeader: some View {
        ListHeader {
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingQueue = false
                        if let coordinator = AppCoordinator.shared {
                            coordinator.isQueueVisible = showingQueue
                        }
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("Play Queue")
                    .headerTitleStyle()
            }

            Spacer()

            queueHeaderControls
        }
    }

    private var queueHeaderControls: some View {
        HStack(spacing: 12) {
            Text("\(playlistManager.currentQueue.count) tracks")
                .headerSubtitleStyle()

            if !playlistManager.currentQueue.isEmpty {
                clearQueueButton
            }
        }
    }

    private var clearQueueButton: some View {
        Button(action: { showingClearConfirmation = true }) {
            Image(systemName: "trash")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear Queue")
    }

    // MARK: - Queue Content

    private var queueContent: some View {
        Group {
            if playlistManager.currentQueue.isEmpty {
                emptyQueueView
            } else {
                queueListView
            }
        }
    }

    // MARK: - Empty Queue View

    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("Queue is Empty")
                .font(.headline)

            Text("Play a song to start building your queue")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Queue List View

    private var queueListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(playlistManager.currentQueue.enumerated()), id: \.element.id) { index, track in
                        queueRow(for: track, at: index)
                            .id(track.id)
                    }
                }
                .padding(.top, 5)
                .padding(.horizontal, 8)
            }
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: playlistManager.currentQueueIndex) { _, newIndex in
                handleQueueIndexChange(newIndex: newIndex, proxy: proxy)
            }
            .onAppear {
                scrollToCurrentTrack(proxy: proxy)
            }
        }
    }

    private func queueRow(for track: Track, at index: Int) -> some View {
        PlayQueueRow(
            track: track,
            position: index,
            isCurrentTrack: index == playlistManager.currentQueueIndex,
            isPlaying: index == playlistManager.currentQueueIndex && playbackManager.isPlaying,
            playlistManager: playlistManager
        ) {
                playlistManager.removeFromQueue(at: index)
        }
        .id(track.id)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onDrag {
            self.draggedTrack = track
            return NSItemProvider(object: track.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: QueueDropDelegate(
            track: track,
            tracks: playlistManager.currentQueue,
            draggedTrack: $draggedTrack,
            playlistManager: playlistManager
        ))
    }

    // MARK: - Helper Methods

    private func handleQueueIndexChange(newIndex: Int, proxy: ScrollViewProxy) {
        // Auto-scroll to current track only after initial appearance
        if hasAppeared && newIndex >= 0 && newIndex < playlistManager.currentQueue.count {
            withAnimation {
                proxy.scrollTo(playlistManager.currentQueue[newIndex].id, anchor: .center)
            }
        }
    }

    private func scrollToCurrentTrack(proxy: ScrollViewProxy) {
        // Scroll to current track on appear
        if playlistManager.currentQueueIndex >= 0 &&
           playlistManager.currentQueueIndex < playlistManager.currentQueue.count {
            proxy.scrollTo(playlistManager.currentQueue[playlistManager.currentQueueIndex].id, anchor: .center)
        }
    }
}

// MARK: - Queue Row Component

struct PlayQueueRow: View {
    let track: Track
    let position: Int
    let isCurrentTrack: Bool
    let isPlaying: Bool
    let playlistManager: PlaylistManager
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            positionIndicator

            trackInfo

            Spacer()

            trackControls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            handleDoubleClick()
        }
    }

    // MARK: - Row Components

    private var positionIndicator: some View {
        ZStack {
            if isCurrentTrack && isPlaying {
                PlayingIndicator()
                    .frame(width: 20)
            } else if isCurrentTrack {
                Image(systemName: "speaker.wave.2")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
            } else {
                Text("\(position + 1)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: 55)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.system(size: 13, weight: isCurrentTrack ? .medium : .regular))
                .lineLimit(1)
                .foregroundColor(isCurrentTrack ? .accentColor : .primary)

            Text(track.artist)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
    }

    private var trackControls: some View {
        HStack(spacing: 5) {
            Text(formatDuration(track.duration))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .monospacedDigit()

            if isHovered && !isCurrentTrack {
                removeButton
            }
        }
    }

    private var removeButton: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isCurrentTrack {
            return Color.accentColor.opacity(0.25)
        } else if isHovered {
            return Color.gray.opacity(0.05)
        } else {
            return Color.clear
        }
    }

    // MARK: - Helper Methods

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }

    private func handleDoubleClick() {
        // Double-click to play
        if !isCurrentTrack {
            playlistManager.playFromQueue(at: position)
        }
    }
}

// MARK: - Drag and Drop Delegate

struct QueueDropDelegate: DropDelegate {
    let track: Track
    let tracks: [Track]
    @Binding var draggedTrack: Track?
    let playlistManager: PlaylistManager

    func performDrop(info: DropInfo) -> Bool {
        true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedTrack = self.draggedTrack else { return }
        
        if draggedTrack.id != track.id {
            // swiftlint:disable:next all
            let from = tracks.firstIndex(where: { $0.id == draggedTrack.id }) ?? 0
            let to = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
            // swiftlint:disable:previous all
            
            withAnimation(.default) {
                playlistManager.moveInQueue(from: from, to: to)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showingQueue = true
    
    return PlayQueueView(showingQueue: $showingQueue)
        .environmentObject({
            let playbackManager = PlaybackManager(
                libraryManager: LibraryManager(),
                playlistManager: PlaylistManager()
            )
            return playbackManager
        }())
        .environmentObject({
            let playlistManager = PlaylistManager()
            // Add some sample tracks to the queue for preview
            let sampleTracks = (0..<5).map { i in
                var track = Track(url: URL(fileURLWithPath: "/path/to/sample\(i).mp3"))
                track.title = "Sample Song \(i)"
                track.artist = "Sample Artist"
                track.album = "Sample Album"
                track.duration = 180.0 + Double(i * 30)
                track.isMetadataLoaded = true
                return track
            }
            playlistManager.currentQueue = sampleTracks
            return playlistManager
        }())
        .frame(width: 350, height: 600)
}

#Preview("Empty Queue") {
    @Previewable @State var showingQueue = true
    
    return PlayQueueView(showingQueue: $showingQueue)
        .environmentObject({
            let playbackManager = PlaybackManager(
                libraryManager: LibraryManager(),
                playlistManager: PlaylistManager()
            )
            return playbackManager
        }())
        .environmentObject(PlaylistManager())
        .frame(width: 350, height: 600)
}
