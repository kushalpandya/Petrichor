import SwiftUI

struct TrackLyricsView: View {
    let onClose: () -> Void
    
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    
    @State private var lyricLines: [LyricLine] = []
    @State private var isLoading = true
    @State private var fetchFailed = false
    @State private var currentLineIndex: Int = -1
    
    private var currentTrack: Track? {
        playbackManager.currentTrack
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            
            if isLoading {
                loadingView
            } else if lyricLines.isEmpty {
                emptyLyricsView
            } else {
                lyricsContent
            }
        }
        .onAppear {
            loadLyricsForCurrentTrack()
        }
        .onChange(of: playbackManager.currentTrack?.id) {
            loadLyricsForCurrentTrack()
        }
        // Listen for playback time changes and update the current line in real time
        .onReceive(playbackManager.$currentTimePublished) { newTime in
            updateCurrentLine(for: newTime)
        }
    }
    
    // MARK: - Header
    private var header: some View {
        ListHeader(opaque: true) {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: Icons.xmarkCircleFill)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("Lyrics")
                    .headerTitleStyle()
            }
            Spacer()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading lyrics...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty Lyrics View
    private var emptyLyricsView: some View {
        VStack(spacing: 16) {
            Image(Icons.customLyrics)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Lyrics Available")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if fetchFailed {
                Button(action: { loadLyricsForCurrentTrack() }) {
                    Label("Retry", systemImage: Icons.arrowClockwise)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Lyrics Content with Synced Highlight
    private var lyricsContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: 14))
                            .fontWeight(currentLineIndex == index ? .bold : .regular)
                            .scaleEffect(currentLineIndex == index ? 1.1 : 1.0)
                            .foregroundColor(currentLineIndex == index ? .primary : .secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .id(index)   // For scrollTo
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentLineIndex)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: currentLineIndex) { oldIndex, newIndex in
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadLyricsForCurrentTrack() {
        guard let track = currentTrack else {
            lyricLines = []
            isLoading = false
            fetchFailed = false
            return
        }
        
        isLoading = true
        lyricLines = []
        fetchFailed = false
        currentLineIndex = -1
        
        Task {
            do {
                let result = try await LyricsLoader.loadLyrics(
                    for: track,
                    using: libraryManager.databaseManager.dbQueue,
                    databaseManager: libraryManager.databaseManager
                )
                
                await MainActor.run {
                    lyricLines = result.lyrics
                    isLoading = false
                    fetchFailed = false
                }
            } catch {
                await MainActor.run {
                    lyricLines = []
                    isLoading = false
                    fetchFailed = true
                }
            }
        }
    }
    
    /// Determine the current lyric line based on playback time
    private func updateCurrentLine(for time: TimeInterval) {
        guard !lyricLines.isEmpty else { return }
        
        // Prefer precise judgment via endTime; fall back to startTime ≤ time when endTime is nil
        let newIndex = lyricLines.lastIndex { line in
            if let end = line.endTime {
                return time >= line.startTime && time < end
            } else {
                return line.startTime <= time
            }
        } ?? -1
        
        if newIndex != currentLineIndex {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentLineIndex = newIndex
            }
        }
    }
}
