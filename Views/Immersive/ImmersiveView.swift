//
// ImmersiveView
//
// An immersive mode showing now playing view along with ability to show
// current playback queue or lyrics on the side.
// Presented as an in-window overlay (a ZStack layer in ContentView) that
// covers the entire main window edge-to-edge.
//

import SwiftUI
import AppKit

private enum ImmersivePanel: String {
    case none
    case queue
    case lyrics
}

private let immersivePanelStateKey = "immersivePanelState"

private struct ImmersiveLayout {
    let scale: CGFloat
    let padding: CGFloat
    let spacing: CGFloat
    let blockWidth: CGFloat
    let artSide: CGFloat
    let blockHeight: CGFloat

    var titleFontSize: CGFloat { 22 * scale }
    var artistFontSize: CGFloat { 16 * scale }
    var titleSpacing: CGFloat { 6 * scale }
    var columnSpacing: CGFloat { 20 * scale }
    var controlsSpacing: CGFloat { 16 * scale }
    var controlsScale: CGFloat { min(scale, 2.0) }
    var lyricsFontSize: CGFloat { 20 * scale }
    var cornerRadius: CGFloat { 12 * scale }
    var headerHorizontalPadding: CGFloat { 16 * scale }
    var headerVerticalPadding: CGFloat { 14 * scale }
    var headerSpacing: CGFloat { 12 * scale }
    var headerTitleFontSize: CGFloat { 15 * scale }
    var headerCaptionFontSize: CGFloat { 12 * scale }
    var headerIconSize: CGFloat { 13 * scale }
}

struct ImmersiveView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager

    /// Owned by ContentView; the close button / Esc set this false to dismiss.
    @Binding var isPresented: Bool

    @Environment(\.colorScheme)
    private var colorScheme

    @AppStorage(immersivePanelStateKey)
    private var panel: ImmersivePanel = .none
    @State private var cachedArtwork: NSImage?
    @State private var currentTrackId: UUID?
    @State private var gradientColors: [Color] = []

    // Cached alongside gradientColors so the ~10 text/border call sites read a
    // stored value instead of re-deriving luminance on every body evaluation.
    @State private var adaptiveText: Color = .white
    @State private var showingClearConfirmation = false

    // Toolbar visibility captured on open and restored on close, so dismissing
    // immersive doesn't force the toolbar visible in a context (e.g. native
    // fullscreen) where AppKit had hidden it.
    @State private var toolbarWasVisible = true

    // Gates the gradient crossfade so the first (seeded) gradient appears instantly
    // and slides up with the view, rather than fading in independently. Later track
    // changes do crossfade.
    @State private var didAppear = false

    /// Artwork/gradient/adaptive color are seeded from ContentView so they're present
    /// on the very first frame; otherwise they'd populate in `onAppear` (after
    /// insertion) and pop/fade in while the view is sliding up.
    init(isPresented: Binding<Bool>, artwork: NSImage?, gradient: [Color], trackID: UUID?) {
        _isPresented = isPresented
        _cachedArtwork = State(initialValue: artwork)
        _gradientColors = State(initialValue: gradient)
        _currentTrackId = State(initialValue: trackID)
        _adaptiveText = State(initialValue: Self.computeAdaptiveText(for: gradient))
    }

    private var hasCurrentTrack: Bool {
        playbackManager.currentTrack != nil
    }

    private var artworkTint: Color {
        NowPlayingArtwork.tint(for: playbackManager.currentTrack)
    }

    /// White or black, whichever keeps text legible against the current background.
    /// Estimated from the displayed gradient's average luminance (already adjusted
    /// for light/dark mode), accounting for the dark scrim drawn over it.
    private static func computeAdaptiveText(for gradient: [Color]) -> Color {
        var total: CGFloat = 0
        var count: CGFloat = 0
        for color in gradient {
            guard let ns = NSColor(color).usingColorSpace(.sRGB) else { continue }
            // The background draws a 0.25 black scrim over the gradient.
            let r = ns.redComponent * 0.75
            let g = ns.greenComponent * 0.75
            let b = ns.blueComponent * 0.75
            total += 0.299 * r + 0.587 * g + 0.114 * b
            count += 1
        }

        // Without artwork colors the immersive background falls back to black plus
        // material/scrim, regardless of system appearance.
        guard count > 0 else { return .white }
        return (total / count) > 0.55 ? .black : .white
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                content(in: geo)
                floatingToolbar
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .background(escapeKeyCatcher)
        .onExitCommand { close() }
        .onAppear {
            // Artwork/gradient/adaptive color are already seeded via init; only the
            // window-toolbar state and the crossfade gate need setting up here.
            toolbarWasVisible = WindowManager.shared.mainWindow?.toolbar?.isVisible ?? true
            setToolbarVisible(false)
            // Open the gradient-crossfade gate after the first frame so subsequent
            // track changes crossfade while the initial gradient slid in untouched.
            DispatchQueue.main.async { didAppear = true }
        }
        .onDisappear {
            setToolbarVisible(toolbarWasVisible)
        }
        .onChange(of: playbackManager.currentTrack?.id) {
            refreshArtwork()
            updateGradientColors()
        }
        .onChange(of: colorScheme) {
            updateGradientColors()
        }
        .clearQueueConfirmation(isPresented: $showingClearConfirmation) {
            playlistManager.clearQueue()
        }
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.black

            if !gradientColors.isEmpty {
                GradientBackground(colors: gradientColors)
                    .animation(didAppear ? .easeInOut(duration: AnimationDuration.standardDuration) : nil, value: gradientColors)
            } else {
                Rectangle().fill(.regularMaterial)
            }

            // A uniform dark scrim keeps the white transport controls, title, and
            // panel chrome legible regardless of light/dark mode or artwork.
            Color.black.opacity(0.25)
        }
        .ignoresSafeArea()
    }

    // MARK: - Content

    private func content(in geo: GeometryProxy) -> some View {
        let layout = makeLayout(for: geo.size)

        return HStack(alignment: .center, spacing: layout.spacing) {
            nowPlayingColumn(layout: layout)

            if panel != .none {
                panelBox(layout: layout)
                    .frame(width: layout.blockWidth, height: layout.blockHeight)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(layout.padding)
        .animation(.easeInOut(duration: AnimationDuration.standardDuration), value: panel)
    }

    private func makeLayout(for size: CGSize) -> ImmersiveLayout {
        // Change the value `20.0` to anything between 0 to 100 to adjust scaling %
        let scale = max(0.8, min(min(size.width / 1440, size.height / 900) * (1 - 15.0 / 100), 2.4))
        let padding = 40 * scale
        let spacing = 100 * scale
        let maxBlockWidth = max(220, (size.width - (padding * 2) - spacing) / 2)
        let blockWidth = max(220, min(460 * scale, maxBlockWidth))
        let reservedHeight = 176 * scale
        let artSide = max(140, min(blockWidth, size.height - (padding * 2) - reservedHeight))
        let blockHeight = artSide + reservedHeight

        return ImmersiveLayout(
            scale: scale,
            padding: padding,
            spacing: spacing,
            blockWidth: blockWidth,
            artSide: artSide,
            blockHeight: blockHeight
        )
    }

    private func nowPlayingColumn(layout: ImmersiveLayout) -> some View {
        VStack(spacing: layout.columnSpacing) {
            artworkView(side: layout.artSide, cornerRadius: layout.cornerRadius)

            VStack(spacing: layout.titleSpacing) {
                Text(playbackManager.currentTrack?.title ?? String(localized: "Not Playing"))
                    .font(.system(size: layout.titleFontSize, weight: .semibold))
                    .foregroundColor(adaptiveText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(playbackManager.currentTrack?.displayArtist ?? "")
                    .font(.system(size: layout.artistFontSize))
                    .foregroundColor(adaptiveText.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: layout.artSide)

            VStack(spacing: layout.controlsSpacing) {
                NowPlayingControlsView(tint: artworkTint, scale: layout.controlsScale)
                NowPlayingProgressBar(tint: artworkTint, scale: layout.controlsScale)
            }
            .frame(width: layout.artSide)
        }
        .frame(width: layout.blockWidth, height: layout.blockHeight)
    }

    @ViewBuilder
    private func artworkView(side: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let image = cachedArtwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Image(systemName: Icons.musicNote)
                            .font(.system(size: side * 0.2, weight: .light))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 24 * (side / 460), x: 0, y: 12 * (side / 460))
    }

    // MARK: - Panel Box

    private func panelBox(layout: ImmersiveLayout) -> some View {
        VStack(spacing: 0) {
            // Lyrics don't need a header; the queue keeps its count / clear action.
            if panel == .queue {
                panelHeader(layout: layout)
                Divider()
                    .background(adaptiveText)
                    .opacity(0.2)
            }
            panelContent(layout: layout)
        }
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layout.cornerRadius, style: .continuous)
                .stroke(adaptiveText.opacity(0.15), lineWidth: 0)
        )
    }

    @ViewBuilder
    private func panelContent(layout: ImmersiveLayout) -> some View {
        switch panel {
        case .queue:
            PlayQueueContent(
                accentColor: artworkTint,
                primaryTextColor: adaptiveText,
                secondaryTextColor: adaptiveText.opacity(0.6),
                scale: layout.scale
            )
        case .lyrics:
            TrackLyricsContent(
                fontSize: layout.lyricsFontSize,
                activeColor: adaptiveText,
                inactiveColor: adaptiveText.opacity(0.55)
            )
        case .none:
            EmptyView()
        }
    }

    // Only rendered for the queue panel (lyrics shows no header), so it's queue-specific.
    private func panelHeader(layout: ImmersiveLayout) -> some View {
        HStack(spacing: layout.headerSpacing) {
            Text("Play Queue")
                .font(.system(size: layout.headerTitleFontSize, weight: .semibold))
                .foregroundColor(adaptiveText)

            Spacer()

            Text("\(playlistManager.currentQueue.count) tracks")
                .font(.system(size: layout.headerCaptionFontSize))
                .foregroundColor(adaptiveText.opacity(0.6))

            if !playlistManager.currentQueue.isEmpty {
                Button {
                    showingClearConfirmation = true
                } label: {
                    Image(systemName: Icons.trash)
                        .font(.system(size: layout.headerIconSize))
                        .foregroundColor(adaptiveText.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Clear Queue")
            }
        }
        .padding(.horizontal, layout.headerHorizontalPadding)
        .padding(.vertical, layout.headerVerticalPadding)
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
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

            Divider()
                .frame(height: 16)

            PanelToolbarButton(
                isActive: false,
                isEnabled: true,
                activeTint: artworkTint,
                activeHelp: String(localized: "Close Immersive Mode"),
                inactiveHelp: String(localized: "Close Immersive Mode"),
                action: { close() },
                label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                }
            )
        }
        .padding(6)
        .floatingControlClusterBackground()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(16)
    }

    // MARK: - Esc handling

    /// A zero-size hidden button bound to Esc. `onExitCommand` alone can miss the
    /// key when focus sits elsewhere in the overlay, so this guarantees the first
    /// Esc closes immersive mode. Once closed, a subsequent Esc is left to the
    /// system (e.g. to exit native fullscreen).
    private var escapeKeyCatcher: some View {
        Button(action: { close() }, label: { EmptyView() })
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func toggle(_ target: ImmersivePanel) {
        withAnimation(.easeInOut(duration: AnimationDuration.standardDuration)) {
            panel = (panel == target) ? .none : target
        }
    }

    private func close() {
        withAnimation(.easeInOut(duration: AnimationDuration.immersiveTransition)) {
            isPresented = false
        }
    }

    // MARK: - Helpers

    /// Hides/shows the main window's toolbar (tab buttons + search). Toggling the
    /// NSToolbar instead of SwiftUI `.windowToolbar` visibility keeps the
    /// titlebar (and its traffic-light buttons) in place.
    private func setToolbarVisible(_ visible: Bool) {
        WindowManager.shared.mainWindow?.toolbar?.isVisible = visible
    }

    private func refreshArtwork() {
        let track = playbackManager.currentTrack
        guard track?.id != currentTrackId || cachedArtwork == nil else { return }

        currentTrackId = track?.id
        cachedArtwork = NowPlayingArtwork.image(for: track)
    }

    private func updateGradientColors() {
        gradientColors = NowPlayingArtwork.gradient(
            for: playbackManager.currentTrack,
            isDark: colorScheme == .dark
        )
        adaptiveText = Self.computeAdaptiveText(for: gradientColors)
    }
}
