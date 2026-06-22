import SwiftUI

struct TrackLyricsView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TrackLyricsContent()
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
}

// MARK: - Lyrics Content (header-less, reusable)

/// The lyrics display (loading / empty / synced scroll) without any header
/// chrome, so it can be hosted inside a custom shell (e.g. the mini player) as
/// well as the main TrackLyricsView. Self-manages loading and line sync.
struct TrackLyricsContent: View {
    /// Font size for lyric lines. Larger hosts (e.g. immersive mode) pass a bigger
    /// value; defaults preserve the compact main-window / mini-player sizing.
    var fontSize: CGFloat = 14
    /// Color for the active (or, for untimed lyrics, every) line.
    var activeColor: Color = .primary
    /// Color for inactive lines.
    var inactiveColor: Color = .secondary

    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager

    @State private var lyricLines: [LyricLine] = []
    @State private var isLoading = true
    @State private var fetchFailed = false
    @State private var currentLineIndex: Int = -1
    @State private var hasTimedLyrics: Bool = false

    private var currentTrack: Track? {
        playbackManager.currentTrack
    }

    var body: some View {
        Group {
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
            // Sample the playhead at 0.5s while lyrics are on screen for tight
            // line highlighting; the rate drops back to 1s when this view closes.
            playbackManager.setFineProgressSampling(true)
        }
        .onDisappear {
            playbackManager.setFineProgressSampling(false)
        }
        .onChange(of: playbackManager.currentTrack?.id) { _, _ in
            loadLyricsForCurrentTrack()
        }
        // Listen for playback time changes and update the current line in real time.
        .onReceive(playbackManager.playbackProgressState.$currentTime) { newTime in
            updateCurrentLine(for: newTime)
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 12) {
            ForEach([170.0, 130.0, 190.0, 110.0], id: \.self) { width in
                Capsule()
                    .fill(inactiveColor)
                    .frame(width: width, height: 13)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A gently pulsing skeleton of lyric lines. PhaseAnimator loops on its own
        // while visible (no extra @State) and restarts each time loading reappears.
        .phaseAnimator(
            [0.3, 0.7],
            content: { view, opacity in
                view.opacity(opacity)
            },
            animation: { _ in .easeInOut(duration: 0.85) }
        )
        .accessibilityLabel("Loading lyrics")
    }

    // MARK: - Empty Lyrics View
    private var emptyLyricsView: some View {
        VStack(spacing: 16) {
            Image(Icons.customLyrics)
                .font(.system(size: 48))
                .foregroundColor(activeColor)

            Text("No Lyrics Available")
                .font(.headline)
                .foregroundColor(activeColor)

            if fetchFailed {
                Button {
                    loadLyricsForCurrentTrack(forceReload: true)
                } label: {
                    Label("Retry", systemImage: Icons.arrowClockwise)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Lyrics Content with Conditional Synced Highlight
    private var lyricsContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: fontSize * 0.7) {
                    ForEach(Array(lyricLines.enumerated()), id: \.offset) { index, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(size: fontSize))
                            // Only apply highlight styles if lyrics are timed
                            .fontWeight(hasTimedLyrics && currentLineIndex == index ? .bold : .regular)
                            .scaleEffect(hasTimedLyrics && currentLineIndex == index ? 1.1 : 1.0)
                            .foregroundColor(hasTimedLyrics && currentLineIndex == index ? activeColor : inactiveColor)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .id(index)   // For scrollTo
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentLineIndex)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
            .onChange(of: currentLineIndex) { _, newIndex in
                // Auto-scroll only for timed lyrics
                guard hasTimedLyrics else { return }
                withAnimation {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func loadLyricsForCurrentTrack(forceReload: Bool = false) {
        guard let track = currentTrack else {
            lyricLines = []
            isLoading = false
            fetchFailed = false
            return
        }

        currentLineIndex = -1
        let loadedTrackId = track.id

        if !forceReload, let cached = LyricsStore.shared.cachedLyrics(for: loadedTrackId) {
            lyricLines = cached.lines
            hasTimedLyrics = cached.hasTimed
            isLoading = false
            fetchFailed = false
            updateCurrentLine(for: playbackManager.playbackProgressState.currentTime)
            return
        }

        isLoading = true
        lyricLines = []
        fetchFailed = false
        hasTimedLyrics = false   // Reset until we know

        Task {
            do {
                // Shared cache + single-flight: concurrent lyrics views (main window,
                // mini player, immersive) for the same track load only once.
                let result = try await LyricsStore.shared.lyrics(
                    for: track,
                    using: libraryManager.databaseManager.dbQueue,
                    databaseManager: libraryManager.databaseManager,
                    forceReload: forceReload
                )

                await MainActor.run {
                    guard currentTrack?.id == loadedTrackId else { return }
                    lyricLines = result.lines
                    hasTimedLyrics = result.hasTimed
                    isLoading = false
                    fetchFailed = false
                }
            } catch {
                await MainActor.run {
                    guard currentTrack?.id == loadedTrackId else { return }
                    lyricLines = []
                    hasTimedLyrics = false
                    isLoading = false
                    fetchFailed = true
                }
            }
        }
    }

    /// Determine the current lyric line based on playback time.
    /// Only executed for timed lyrics; for untimed lyrics this does nothing.
    private func updateCurrentLine(for time: TimeInterval) {
        guard hasTimedLyrics, !lyricLines.isEmpty else { return }

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
