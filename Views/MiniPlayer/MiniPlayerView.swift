//
// MiniPlayerView
//
// Root view of the mini player window. Shows edge-to-edge album artwork with
// playback controls + progress revealed on hover behind a glass scrim, and a
// floating top-right toolbar (Queue / Lyrics) that expands the window taller to
// show those panels (over an artwork-derived gradient) below the artwork.
//
// The window is user-resizable: it scales proportionally, always keeping the
// artwork square, between a minimum and maximum side. Sizing is driven against
// the captured NSWindow (aspect ratio + min/max) rather than SwiftUI's automatic
// window sizing.
//

import SwiftUI
import AppKit

private enum MiniPlayerPanel: String {
    case none
    case queue
    case lyrics
}

private let miniPlayerPanelStateKey = "miniPlayerPanelState"

/// Glass-like backdrop that fades from transparent at the top into a blurred scrim at
/// the bottom, so the controls blend into the artwork rather than a hard opaque panel.
/// Kept separate (and Equatable) so it only re-renders when the scrim color changes,
/// not on the mini player's play/pause re-renders.
private struct MiniPlayerControlScrim: View, Equatable {
    let scrimColor: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.clear, scrimColor.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )

            FocusStableMaterial()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.5), location: 0.45),
                            .init(color: .black.opacity(0.9), location: 0.75),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .allowsHitTesting(false)
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager

    @Environment(\.colorScheme)
    private var colorScheme
    @AppStorage("miniPlayerAlwaysOnTop")
    private var miniPlayerAlwaysOnTop = false
    @AppStorage("useArtworkColors")
    private var useArtworkColors = true
    @AppStorage("tintPlaybackControls")
    private var tintPlaybackControls = true
    @AppStorage("tintNowPlayingBackground")
    private var tintNowPlayingBackground = true
    // Persisted independently from the main window's queue/lyrics state so the
    // mini player remembers its own panel across relaunches.
    @AppStorage(miniPlayerPanelStateKey)
    private var panel: MiniPlayerPanel = .none

    @State private var isHovering = false
    @State private var cachedArtwork: NSImage?
    @State private var currentTrackId: UUID?
    @State private var miniWindow: NSWindow?
    @State private var gradientColors: [Color] = []
    @State private var showingClearConfirmation = false
    @State private var dragStartOrigin: CGPoint?
    @State private var dragStartMouse: CGPoint?

    private let minSide: CGFloat = 260
    private let maxSide: CGFloat = 560
    // Extra height (as a fraction of the artwork side) added below the square
    // artwork when a panel is open. Keeping it proportional preserves a constant
    // window aspect ratio, so the artwork stays square at every size.
    private let panelRatio: CGFloat = 1.15

    // Borderless windows don't get the system's corner radius, so we clip to
    // match it ourselves. macOS 26 (Tahoe) uses noticeably rounder window
    // corners than earlier releases.
    private var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 24
        } else {
            return 10
        }
    }

    private var hasCurrentTrack: Bool {
        playbackManager.currentTrack != nil
    }

    /// Artwork's primary dominant color, used to tint the play/pause button,
    /// progress bar, and the queue's current-track highlight. Falls back to the
    /// accent color when artwork colors are unavailable or disabled.
    /// `dominantColors` is cached per track, so this is cheap.
    private var controlsUseArtworkTint: Bool {
        useArtworkColors && tintPlaybackControls
    }

    private var backgroundUsesArtwork: Bool {
        useArtworkColors && tintNowPlayingBackground
    }

    private var artworkTint: Color {
        NowPlayingArtwork.tint(for: playbackManager.currentTrack, useArtworkTint: controlsUseArtworkTint)
    }

    /// Legible, mode-adjusted dominant color for the secondary controls, keyed off
    /// the actual scrim luminance (not just the appearance) so it stays readable even
    /// when an artwork-tinted scrim is darker/lighter than the mode would suggest.
    private var controlColor: Color {
        NowPlayingArtwork.controlColor(
            for: playbackManager.currentTrack,
            useArtworkTint: controlsUseArtworkTint,
            isDarkBackground: overlayIsDark
        )
    }

    /// Prev/next icon color: the artwork control color when tinting is on, otherwise
    /// the adaptive overlay color so it stays readable over the scrim.
    private var transportColor: Color {
        controlsUseArtworkTint ? controlColor : overlayTextColor
    }

    /// Bottom color of the hover scrim: a mode-aware muted dominant when the Mini
    /// Player / Immersive background tint is on, otherwise the plain window backdrop
    /// (light in light mode, dark in dark mode) so the controls read exactly like the
    /// main player bar. This is a background, so it follows the background tint toggle
    /// rather than the controls toggle.
    private var controlScrimColor: Color {
        let fallback: Color = colorScheme == .dark ? .black : .white
        guard backgroundUsesArtwork, let dominant = playbackManager.currentTrack?.dominantColors.first else {
            return fallback
        }
        return ImageUtils.backgroundGradientColors(from: [dominant], isDark: colorScheme == .dark).first ?? fallback
    }

    /// Whether the scrim behind the hover overlay reads as dark, from its dominant
    /// color's luminance. Mirrors the immersive overlay's adaptive-text logic so the
    /// title/artist and control glyphs flip black/white to stay readable.
    private var overlayIsDark: Bool {
        NowPlayingArtwork.luminance(of: controlScrimColor) < 0.6
    }

    /// Black or white, whichever keeps the overlay text/glyphs legible over the scrim.
    private var overlayTextColor: Color {
        overlayIsDark ? .white : .black
    }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                artwork(side: geo.size.width)

                if panel != .none {
                    expandedPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
        }
        .frame(minWidth: minSide, minHeight: minSide)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .captureMiniPlayerWindow { window in
            miniWindow = window
            applyWindowSizing(animated: false)
            applyWindowLevel()
            roundWindowCorners(window)
        }
        .onAppear {
            refreshArtwork()
            updateGradientColors()
        }
        .onChange(of: miniPlayerAlwaysOnTop) {
            applyWindowLevel()
        }
        .onChange(of: playbackManager.currentTrack?.id) {
            refreshArtwork()
            updateGradientColors()
        }
        .onChange(of: colorScheme) {
            updateGradientColors()
        }
        .onChange(of: backgroundUsesArtwork) {
            updateGradientColors()
        }
    }

    // MARK: - Artwork + Overlays

    private func artwork(side: CGFloat) -> some View {
        ZStack(alignment: .top) {
            artworkImage(side: side)

            windowButtons
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeInOut(duration: 0.2), value: isHovering)

            topToolbar
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeInOut(duration: 0.2), value: isHovering)

            bottomControls
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .frame(width: side, height: side)
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        // Right-click anywhere on the artwork (but not the queue/lyrics drawer below).
        .contextMenu {
            Toggle("Keep always on top", isOn: $miniPlayerAlwaysOnTop)
        }
    }

    @ViewBuilder
    private func artworkImage(side: CGFloat) -> some View {
        Group {
            if let image = cachedArtwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .contentShape(Rectangle())
        .gesture(windowMoveGesture)
    }

    private var windowButtons: some View {
        VStack {
            HStack {
                MiniPlayerWindowButtons(window: miniWindow)
                Spacer()
            }
            Spacer()
        }
        .padding(12)
    }

    private var topToolbar: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    PanelToolbarButton(
                        isActive: panel == .queue,
                        isEnabled: true,
                        activeTint: artworkTint,
                        activeHelp: String(localized: "Hide Queue"),
                        inactiveHelp: String(localized: "Show Queue"),
                        action: { toggle(.queue) },
                        label: {
                            Image(systemName: Icons.queueList)
                                .font(.system(size: 13))
                        }
                    )

                    PanelToolbarButton(
                        isActive: panel == .lyrics,
                        isEnabled: hasCurrentTrack,
                        activeTint: artworkTint,
                        activeHelp: String(localized: "Hide Lyrics"),
                        inactiveHelp: String(localized: "Show Lyrics"),
                        action: { toggle(.lyrics) },
                        label: {
                            Image(Icons.customLyrics)
                        }
                    )
                }
                .padding(6)
                .floatingControlClusterBackground()
            }
            Spacer()
        }
        .padding(12)
    }

    private var bottomControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text(playbackManager.currentTrack?.title ?? String(localized: "Not Playing"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(overlayTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(playbackManager.currentTrack?.displayArtist ?? "")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(overlayTextColor.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
                // A shadow opposite the adaptive text color softly separates it from
                // the artwork showing through the upper, more transparent scrim.
                .shadow(color: (overlayIsDark ? Color.black : Color.white).opacity(0.5), radius: 3, x: 0, y: 1)

                NowPlayingControlsView(
                    tint: artworkTint,
                    accent: controlColor,
                    transport: transportColor,
                    neutral: overlayTextColor
                )

                NowPlayingProgressBar(accent: controlColor, neutral: overlayTextColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 120)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .background(MiniPlayerControlScrim(scrimColor: controlScrimColor).equatable())
        }
    }

    // MARK: - Expanded Panel

    @ViewBuilder private var expandedPanel: some View {
        ZStack {
            // Artwork-derived gradient behind the panel, like TrackDetailView.
            if !gradientColors.isEmpty {
                LinearGradient(
                    colors: gradientColors + [.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(FocusStableMaterial())
                .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: gradientColors)
            }

            VStack(spacing: 0) {
                panelHeader
                panelContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .clearQueueConfirmation(isPresented: $showingClearConfirmation) {
            playlistManager.clearQueue()
        }
    }

    @ViewBuilder private var panelContent: some View {
        switch panel {
        case .queue:
            PlayQueueContent(accentColor: artworkTint)
        case .lyrics:
            TrackLyricsContent()
        case .none:
            EmptyView()
        }
    }

    private var panelHeader: some View {
        HStack(spacing: 12) {
            Button {
                collapsePanel()
            } label: {
                Image(systemName: Icons.xmarkCircleFill)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Text(panel == .queue ? String(localized: "Play Queue") : String(localized: "Lyrics"))
                .font(.headline)

            Spacer()

            if panel == .queue {
                Text("\(playlistManager.currentQueue.count) tracks")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !playlistManager.currentQueue.isEmpty {
                    Button {
                        showingClearConfirmation = true
                    } label: {
                        Image(systemName: Icons.trash)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Queue")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(windowMoveGesture)
    }

    // MARK: - Window Move

    /// Moves the window by dragging the artwork / panel header. Uses screen-space
    /// mouse deltas (stable as the window moves) so it doesn't rely on
    /// `isMovableByWindowBackground`, which would otherwise fight queue reordering.
    private var windowMoveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                guard let window = miniWindow else { return }
                if dragStartOrigin == nil {
                    dragStartOrigin = window.frame.origin
                    dragStartMouse = NSEvent.mouseLocation
                }
                guard let startOrigin = dragStartOrigin, let startMouse = dragStartMouse else { return }
                let current = NSEvent.mouseLocation
                window.setFrameOrigin(NSPoint(
                    x: startOrigin.x + (current.x - startMouse.x),
                    y: startOrigin.y + (current.y - startMouse.y)
                ))
            }
            .onEnded { _ in
                dragStartOrigin = nil
                dragStartMouse = nil
            }
    }

    // MARK: - Helpers

    private func toggle(_ target: MiniPlayerPanel) {
        if panel == target {
            collapsePanel()
        } else {
            panel = target
            applyWindowSizing(animated: true)
        }
    }

    private func collapsePanel() {
        guard panel != .none else { return }
        // Shrink the window while the (possibly tinted) panel is still rendered, so
        // its background doesn't briefly flash to the window color, then drop the
        // panel once the resize finishes. The small buffer guards against removing it
        // a frame before the animation lands.
        let collapsing = panel
        let duration = applyWindowSizing(animated: true, expanded: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
            // Skip if a different panel was opened during the collapse animation.
            if panel == collapsing { panel = .none }
        }
    }

    private func refreshArtwork() {
        let track = playbackManager.currentTrack
        guard track?.id != currentTrackId || cachedArtwork == nil else { return }

        currentTrackId = track?.id
        cachedArtwork = NowPlayingArtwork.image(for: track)
    }

    private func applyWindowLevel() {
        miniWindow?.level = miniPlayerAlwaysOnTop ? .floating : .normal
    }

    /// Rounds the hosting content view's layer to match the SwiftUI corner clip.
    /// Without this the opaque NSHostingView's square corners show through as a
    /// sliver behind the rounded clip.
    private func roundWindowCorners(_ window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
    }

    private func updateGradientColors() {
        gradientColors = NowPlayingArtwork.gradient(
            for: playbackManager.currentTrack,
            isDark: colorScheme == .dark,
            enabled: backgroundUsesArtwork
        )
    }

    // MARK: - Window Sizing

    /// Applies the aspect ratio / min / max for the current panel state and
    /// resizes to fit, keeping the artwork square and pinning the top-left corner
    /// so growth happens downward. The target frame is computed synchronously so
    /// the (resize) animation duration can be returned to the caller; the window
    /// is mutated async so this never runs during a SwiftUI layout pass.
    /// - Returns: the resize animation duration (0 when not animated).
    @discardableResult
    private func applyWindowSizing(animated: Bool, expanded: Bool? = nil) -> TimeInterval {
        guard let window = miniWindow else { return 0 }

        let isExpanded = expanded ?? (panel != .none)
        let ratioH = isExpanded ? (1 + panelRatio) : 1
        let width = min(max(window.contentLayoutRect.width, minSide), maxSide)
        let contentSize = NSSize(width: width, height: width * ratioH)
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size

        var origin = window.frame.origin
        origin.y = window.frame.maxY - frameSize.height
        let frame = NSRect(origin: origin, size: frameSize)
        let duration = animated ? window.animationResizeTime(frame) : 0

        DispatchQueue.main.async {
            window.contentAspectRatio = NSSize(width: 1, height: ratioH)
            window.contentMinSize = NSSize(width: minSide, height: minSide * ratioH)
            window.contentMaxSize = NSSize(width: maxSide, height: maxSide * ratioH)
            window.setFrame(frame, display: true, animate: animated)
        }

        return duration
    }
}
