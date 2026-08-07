import SwiftUI

struct PlayerStationArtView: View, Equatable {
    /// Changes when the artwork does, so editing a playing station's image re-renders.
    let artworkID: UUID
    let artworkData: Data?

    static func == (lhs: PlayerStationArtView, rhs: PlayerStationArtView) -> Bool {
        lhs.artworkID == rhs.artworkID
    }

    var body: some View {
        AlbumArtworkImage(artworkData: artworkData, placeholderIcon: Icons.radioFill, interactive: false)
    }
}

struct PlayerStationDetailsView: View, Equatable {
    let stationName: String
    let nowPlaying: String?
    let description: String?
    let format: StreamFormat?
    let showTechnicalInfo: Bool

    static func == (lhs: PlayerStationDetailsView, rhs: PlayerStationDetailsView) -> Bool {
        lhs.stationName == rhs.stationName &&
        lhs.nowPlaying == rhs.nowPlaying &&
        lhs.description == rhs.description &&
        lhs.showTechnicalInfo == rhs.showTechnicalInfo &&
        lhs.format == rhs.format
    }

    // Matches PlayerTrackDetailsView's metrics so the block doesn't shift.
    private var titleFontSize: CGFloat { showTechnicalInfo ? 14 : 16 }
    private var nowPlayingFontSize: CGFloat { showTechnicalInfo ? 12 : 14 }
    private var descriptionFontSize: CGFloat { showTechnicalInfo ? 11 : 13 }
    private var rowSpacing: CGFloat { showTechnicalInfo ? 4 : 10 }
    private var titleRowHeight: CGFloat { showTechnicalInfo ? 16 : 20 }
    private var textRowHeight: CGFloat { showTechnicalInfo ? 15 : 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            Text(stationName)
                .font(.system(size: titleFontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(stationName)
                .frame(height: titleRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Only the live line scrolls; a second permanent marquee would burn CPU.
            MarqueeText(
                text: nowPlaying ?? "",
                font: .system(size: nowPlayingFontSize),
                color: .secondary
            )
            .frame(height: textRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(description ?? "")
                .font(.system(size: descriptionFontSize))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(description ?? "")
                .frame(height: textRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showTechnicalInfo {
                formatBadgeRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formatBadgeRow: some View {
        HStack(spacing: 4) {
            if let format {
                if let codec = format.codec, !codec.isEmpty {
                    FormatBadge(text: codec.uppercased())
                }
                // The engine reports bits per second; the rest of the UI shows kbps.
                if let bitrate = format.bitrate, bitrate > 0 {
                    FormatBadge(text: "\(bitrate / 1000) kbps")
                }
                if format.sampleRate > 0 {
                    FormatBadge(text: String(format: "%.1f kHz", format.sampleRate / 1000))
                }
                if format.channelCount > 0 {
                    FormatBadge(text: format.channelCount == 1
                        ? String(localized: "Mono")
                        : String(localized: "Stereo"))
                }
            }
        }
        .frame(height: 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `Equatable` so the once-a-second progress tick can't re-drive the sweep.
struct StreamProgressTrack: View, Equatable {
    let accent: Color
    let isBuffering: Bool
    let isPlaying: Bool

    static func == (lhs: StreamProgressTrack, rhs: StreamProgressTrack) -> Bool {
        lhs.isBuffering == rhs.isBuffering && lhs.isPlaying == rhs.isPlaying && lhs.accent == rhs.accent
    }

    static let barHeight: CGFloat = 4

    var body: some View {
        ZStack(alignment: .leading) {
            if isBuffering {
                StreamBufferingBar(accent: accent, barHeight: Self.barHeight)
            } else {
                RoundedRectangle(cornerRadius: Self.barHeight / 2)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: Self.barHeight)

                if isPlaying {
                    RoundedRectangle(cornerRadius: Self.barHeight / 2)
                        .fill(accent.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.barHeight)
                }
            }
        }
    }
}

/// Shared by both progress bars so the live badge and duration stay in step.
struct ProgressTrailingSlot: View {
    let accent: Color
    let isStream: Bool
    let isPlaying: Bool
    let isBuffering: Bool
    let duration: Double
    let slotWidth: CGFloat
    let font: Font
    var textColor: Color = .secondary
    var compactBadge = false

    var body: some View {
        Group {
            if isStream {
                LiveIndicator(accent: accent, isLive: isPlaying, isConnecting: isBuffering, compact: compactBadge)
                    .equatable()
            } else {
                Text(HelperUtils.formattedDuration(duration))
                    .font(font)
                    .foregroundColor(textColor)
                    .monospacedDigit()
            }
        }
        .frame(width: slotWidth, alignment: .leading)
    }
}

/// The pulse is a `TimelineView`, **not** `repeatForever`: a perpetual SwiftUI animation
/// re-runs the whole player bar's layout every frame and sits at ~30% CPU while streaming.
struct LiveIndicator: View, Equatable {
    let accent: Color
    let isLive: Bool
    let isConnecting: Bool
    /// Dots only, for the mini player and immersive bars: the words belong to the main
    /// window, and reserving room for CONNECTING there would leave 52pt of bar.
    var compact = false

    private static let pulsePeriod: TimeInterval = 0.9

    /// What CONNECTING needs; the full-size row holds both side slots at this width.
    static let connectingSlotWidth: CGFloat = 80

    static func == (lhs: LiveIndicator, rhs: LiveIndicator) -> Bool {
        lhs.isLive == rhs.isLive && lhs.isConnecting == rhs.isConnecting && lhs.accent == rhs.accent
    }

    // `Color.clear` rather than nothing: `.frame(width:)` reserves no width around an
    // `EmptyView`, which drops the slot and shifts the bar off-centre.
    var body: some View {
        if isConnecting {
            badge(color: accent.opacity(0.7), dimmed: 0.2) { compact ? nil : Text("CONNECTING") }
        } else if isLive {
            badge(color: .red, dimmed: 0.3) { compact ? nil : Text("LIVE") }
        } else {
            Color.clear.frame(height: 0)
        }
    }

    // `Text?` not a ternary: a ternary over string literals yields `String` and loses the
    // automatic `LocalizedStringKey` lookup. `nil` is the dot on its own.
    private func badge(color: Color, dimmed: Double, label: () -> Text?) -> some View {
        HStack(spacing: 4) {
            TimelineView(.periodic(from: .now, by: Self.pulsePeriod)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / Self.pulsePeriod) % 2
                Circle()
                    .fill(color)
                    .opacity(phase == 0 ? 1 : dimmed)
            }
            .frame(width: 6, height: 6)

            label()
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }
}

/// Indeterminate sweep for the stream-connect window, drawn with CoreAnimation.
/// Not `ProgressView(.linear)`: `NSProgressIndicator` keeps its own intrinsic thickness
/// and can't be matched to the live bar's height. Not `repeatForever` either: that drives
/// a layout pass every frame on the same main thread that is busy opening the stream.
struct StreamBufferingBar: NSViewRepresentable {
    let accent: Color
    let barHeight: CGFloat

    func makeNSView(context: Context) -> BufferingBarView {
        let view = BufferingBarView()
        view.configure(accent: NSColor(accent), barHeight: barHeight)
        return view
    }

    func updateNSView(_ nsView: BufferingBarView, context: Context) {
        nsView.configure(accent: NSColor(accent), barHeight: barHeight)
    }
}

final class BufferingBarView: NSView {
    private let track = CALayer()
    private let segment = CALayer()
    private var barHeight: CGFloat = 4
    private var animatedWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.addSublayer(track)
        layer?.addSublayer(segment)
    }

    func configure(accent: NSColor, barHeight: CGFloat) {
        self.barHeight = barHeight
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.2).cgColor
        segment.backgroundColor = accent.withAlphaComponent(0.6).cgColor
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let midY = (bounds.height - barHeight) / 2
        let segmentWidth = max(24, bounds.width * 0.3)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = CGRect(x: 0, y: midY, width: bounds.width, height: barHeight)
        track.cornerRadius = barHeight / 2
        segment.bounds = CGRect(x: 0, y: 0, width: segmentWidth, height: barHeight)
        segment.cornerRadius = barHeight / 2
        segment.position = CGPoint(x: segmentWidth / 2, y: midY + barHeight / 2)
        CATransaction.commit()

        // Only on a real width change, or the segment jumps back to the left edge.
        guard bounds.width != animatedWidth else { return }
        animatedWidth = bounds.width
        startSweep(segmentWidth: segmentWidth)
    }

    private func startSweep(segmentWidth: CGFloat) {
        segment.removeAnimation(forKey: "sweep")
        guard bounds.width > segmentWidth else { return }

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = segmentWidth / 2
        sweep.toValue = bounds.width - segmentWidth / 2
        sweep.duration = 1.1
        sweep.autoreverses = true
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        segment.add(sweep, forKey: "sweep")
    }
}
