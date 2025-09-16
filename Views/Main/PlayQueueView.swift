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
            queueHeader
            Divider()

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
        .onAppear { hasAppeared = true }
        .onDisappear { hasAppeared = false }
    }

    // MARK: - Queue Header

    private var queueHeader: some View {
        ListHeader {
            HStack(spacing: 12) {
                Button(action: {
                    showingQueue = false
                    AppCoordinator.shared?.isQueueVisible = showingQueue
                }) {
                    Image(systemName: Icons.xmarkCircleFill)
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
            Image(systemName: Icons.trash)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear Queue")
    }

    // MARK: - Empty Queue View

    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Image(systemName: Icons.musicNoteList)
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
    }

    // MARK: - Queue List View (List-based)

    private var queueListView: some View {
        List {
            ForEach(playlistManager.currentQueue, id: \.id) { track in
                queueRow(for: track)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            .onMove(perform: moveTracks)
        }
        .listStyle(.plain)
        .safeAreaPadding(.vertical, 6)
    }

    private func queueRow(for track: Track) -> some View {
        // swiftlint:disable:next trailing_closure
        let position = playlistManager.currentQueue.firstIndex(where: { $0.id == track.id }) ?? 0
        let isLastItem = position == playlistManager.currentQueue.count - 1

        return PlayQueueRow(
            track: track,
            position: position,
            isCurrentTrack: position == playlistManager.currentQueueIndex,
            isPlaying: position == playlistManager.currentQueueIndex && playbackManager.isPlaying,
            playlistManager: playlistManager,
            isLastItem: isLastItem
        ) {
            playlistManager.removeFromQueue(at: position)
        }
        .onDrag {
            draggedTrack = track
            return NSItemProvider(object: track.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: QueueDropDelegate(
            track: track,
            tracks: playlistManager.currentQueue,
            draggedTrack: $draggedTrack,
            playlistManager: playlistManager
        ))
    }

    // MARK: - List move/delete helpers

    private func moveTracks(from offsets: IndexSet, to destination: Int) {
        let sortedOffsets = offsets.sorted(by: >)
        
        for offset in sortedOffsets {
            let adjustedDestination = destination > offset ? destination - 1 : destination
            playlistManager.moveInQueue(from: offset, to: adjustedDestination)
        }
    }

    private func removeTracks(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            playlistManager.removeFromQueue(at: offset)
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
    let isLastItem: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            positionIndicator
            trackInfo
            Spacer()
            trackControls
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(rowBackground)
        .contentShape(Rectangle())
        .overlay(
            isLastItem ? nil : Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.secondary.opacity(0.3))
                .padding(.horizontal, 14),
            alignment: .bottom
        )
        .onHover { hovering in
            if hovering != isHovered {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        }
        .onTapGesture(count: 2) { handleDoubleClick() }
    }

    private var positionIndicator: some View {
        ZStack {
            if isCurrentTrack || isPlaying {
                Image(systemName: isPlaying ? Icons.playFill : Icons.pauseFill)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
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
                .font(.system(size: 13, weight: isCurrentTrack ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isCurrentTrack ? .white : .primary)

            Text(track.artist)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(isCurrentTrack ? .white : .secondary)
        }
    }

    private var trackControls: some View {
        HStack(spacing: 5) {
            Text(formatDuration(track.duration))
                .font(.system(size: 11))
                .foregroundColor(isCurrentTrack ? .white : .secondary)
                .monospacedDigit()

            if isHovered && !isCurrentTrack {
                removeButton
            }
        }
    }

    private var removeButton: some View {
        Button(action: {
            playlistManager.removeFromQueue(at: position)
        }) {
            Image(systemName: Icons.xmarkCircleFill)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .help("Remove from queue")
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    private var rowBackground: some View {
        ZStack {
            if isCurrentTrack {
                Color.accentColor
            } else if isHovered {
                Color.accentColor.opacity(0.1)
            } else {
                Color.clear
            }
        }
        .cornerRadius(6)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: StringFormat.mmss, minutes, remainingSeconds)
    }

    private func handleDoubleClick() {
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

    func performDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        guard let draggedTrack = self.draggedTrack else { return }
        if draggedTrack.id != track.id {
            // swiftlint:disable:next trailing_closure
            let from = tracks.firstIndex(where: { $0.id == draggedTrack.id }) ?? 0
            // swiftlint:disable:next trailing_closure
            let to = tracks.firstIndex(where: { $0.id == track.id }) ?? 0
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
