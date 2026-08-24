import AppKit
import Combine
import SwiftUI

private struct NativeProgressConfiguration {
    let accent: NSColor
    let neutral: NSColor
    let scale: CGFloat
    let compactStreamIndicator: Bool
    let isStream: Bool
    let isBuffering: Bool
    let isPlaying: Bool
    let duration: Double
}

/// Keeps periodic progress changes out of SwiftUI's layout graph. The native
/// view updates its labels and layers directly from `PlaybackProgressState`.
struct PlayerProgressBar: NSViewRepresentable {
    let accent: Color
    var neutral: Color = .secondary
    var scale: CGFloat = 1
    var compactStreamIndicator = false

    static let trackWidth: CGFloat = 400
    static let sideSlotWidth: CGFloat = 80
    static let preferredWidth: CGFloat = trackWidth + 2 * (sideSlotWidth + 8)

    @EnvironmentObject private var playbackManager: PlaybackManager

    func makeNSView(context: Context) -> NativePlayerProgressView {
        NativePlayerProgressView(playbackManager: playbackManager)
    }

    func updateNSView(_ view: NativePlayerProgressView, context: Context) {
        let streamIsBuffering = playbackManager.radioConnectionPhase == .connecting ||
            playbackManager.radioConnectionPhase == .reconnecting
        let streamIsLive = playbackManager.radioConnectionPhase == .playing
        view.configure(NativeProgressConfiguration(
            accent: NSColor(accent),
            neutral: NSColor(neutral),
            scale: scale,
            compactStreamIndicator: compactStreamIndicator,
            isStream: playbackManager.hasStation,
            isBuffering: streamIsBuffering,
            isPlaying: streamIsLive,
            duration: playbackManager.currentTrack?.duration ?? 0
        ))
    }
}

final class NativePlayerProgressView: NSView {
    private weak var playbackManager: PlaybackManager?
    private var progressSubscription: AnyCancellable?
    private var displayOptionsSubscription: AnyCancellable?
    private var trackingArea: NSTrackingArea?

    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let trailingLabel = NSTextField(labelWithString: "0:00")
    private let trackLayer = CALayer()
    private let fillLayer = CALayer()
    private let bufferingLayer = CALayer()
    private let liveDotLayer = CALayer()
    private let thumbLayer = CALayer()

    private var accent = NSColor.controlAccentColor
    private var neutral = NSColor.secondaryLabelColor
    private var scale: CGFloat = 1
    private var compactStreamIndicator = false
    private var duration: Double = 0
    private var currentTime: Double = 0
    private var isStream = false
    private var isBuffering = false
    private var isPlaying = false
    private var isDragging = false
    private var isHovering = false
    private var trackID: UUID?
    private var animatedTrackFrame = CGRect.zero

    // MARK: - Lifecycle

    init(playbackManager: PlaybackManager) {
        self.playbackManager = playbackManager
        super.init(frame: .zero)
        setup()
        progressSubscription = playbackManager.playbackProgressState.$currentTime
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] time in
                self?.setProgress(time, animated: true)
            }
        displayOptionsSubscription = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateStreamAnimations(bufferWidth: max(24, self.trackFrame.width * 0.3))
            }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 14 * scale)
    }

    // MARK: - Configuration

    fileprivate func configure(_ configuration: NativeProgressConfiguration) {
        let nextTrackID = playbackManager?.currentTrack?.id
        if nextTrackID != trackID {
            trackID = nextTrackID
            isDragging = false
            currentTime = playbackManager?.playbackProgressState.currentTime ?? 0
        }
        accent = configuration.accent
        neutral = configuration.neutral
        if scale != configuration.scale {
            scale = configuration.scale
            invalidateIntrinsicContentSize()
        }
        compactStreamIndicator = configuration.compactStreamIndicator
        isStream = configuration.isStream
        isBuffering = configuration.isBuffering
        isPlaying = configuration.isPlaying
        duration = configuration.duration
        updateLabelStyle()
        updateColors()
        updateLabels()
        setProgress(currentTime, animated: false)
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = false

        for label in [elapsedLabel, trailingLabel] {
            label.alignment = label === elapsedLabel ? .right : .left
            addSubview(label)
        }
        updateLabelStyle()

        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(bufferingLayer)
        layer?.addSublayer(liveDotLayer)
        layer?.addSublayer(thumbLayer)
        updateColors()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let sideWidth = sideSlotWidth
        elapsedLabel.frame = NSRect(x: 0, y: 0, width: sideWidth, height: bounds.height)
        trailingLabel.frame = NSRect(x: bounds.width - sideWidth, y: 0, width: sideWidth, height: bounds.height)
        setProgress(currentTime, animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: trackFrame.insetBy(dx: -4, dy: -3),
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Interaction

    override func mouseEntered(with event: NSEvent) {
        guard !isStream, duration > 0 else { return }
        isHovering = true
        updateThumbVisibility()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateThumbVisibility()
    }

    override func mouseDown(with event: NSEvent) {
        guard !isStream, duration > 0,
              trackFrame.insetBy(dx: -4, dy: -3).contains(convert(event.locationInWindow, from: nil)) else { return }
        isDragging = true
        updateProgress(at: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateProgress(at: convert(event.locationInWindow, from: nil).x)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        updateProgress(at: convert(event.locationInWindow, from: nil).x)
        isDragging = false
        updateThumbVisibility()
        playbackManager?.seekTo(time: currentTime)
    }

    // MARK: - Progress

    private var trackFrame: CGRect {
        let sideWidth = sideSlotWidth
        let spacing = 8 * scale
        let trackHeight = 4 * scale
        return CGRect(
            x: sideWidth + spacing,
            y: (bounds.height - trackHeight) / 2,
            width: max(0, bounds.width - 2 * (sideWidth + spacing)),
            height: trackHeight
        )
    }

    private var sideSlotWidth: CGFloat {
        compactStreamIndicator ? 50 * scale : PlayerProgressBar.sideSlotWidth
    }

    private var thumbSize: CGFloat {
        compactStreamIndicator ? 10 * scale : 12
    }

    private func updateProgress(at x: CGFloat) {
        let frame = trackFrame
        guard frame.width > 0 else { return }
        let fraction = min(1, max(0, (x - frame.minX) / frame.width))
        currentTime = fraction * HelperUtils.sanitizedDuration(duration)
        setProgress(currentTime, animated: false)
    }

    private func setProgress(_ time: Double, animated: Bool) {
        if isDragging && animated { return }
        currentTime = HelperUtils.sanitizedDuration(time)
        updateLabels()

        let frame = trackFrame
        let fraction = duration > 0 ? min(1, max(0, currentTime / duration)) : 0
        let fillWidth = isStream ? (isPlaying && !isBuffering ? frame.width : 0) : frame.width * fraction
        let bufferWidth = max(24, frame.width * 0.3)
        let dotSize = 6 * scale
        let thumbSize = thumbSize

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.2 : 0)
        trackLayer.frame = frame
        fillLayer.frame = CGRect(x: frame.minX, y: frame.minY, width: fillWidth, height: frame.height)
        bufferingLayer.bounds = CGRect(x: 0, y: 0, width: bufferWidth, height: frame.height)
        bufferingLayer.position = CGPoint(x: frame.minX + bufferWidth / 2, y: frame.midY)
        bufferingLayer.zPosition = 1
        liveDotLayer.frame = CGRect(
            x: bounds.width - sideSlotWidth,
            y: (bounds.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        liveDotLayer.zPosition = 1
        thumbLayer.frame = CGRect(
            x: frame.minX + frame.width * fraction - thumbSize / 2,
            y: (bounds.height - thumbSize) / 2,
            width: thumbSize,
            height: thumbSize
        )
        trackLayer.cornerRadius = frame.height / 2
        fillLayer.cornerRadius = frame.height / 2
        bufferingLayer.cornerRadius = frame.height / 2
        liveDotLayer.cornerRadius = dotSize / 2
        thumbLayer.cornerRadius = thumbSize / 2
        CATransaction.commit()
        updateStreamAnimations(bufferWidth: bufferWidth)
        updateThumbVisibility()
    }

    // MARK: - Appearance

    private func updateLabels() {
        elapsedLabel.stringValue = HelperUtils.formattedDuration(currentTime)
        if isStream {
            if compactStreamIndicator {
                trailingLabel.stringValue = ""
            } else {
                trailingLabel.stringValue = isBuffering
                    ? String(localized: "CONNECTING")
                    : (isPlaying ? String(localized: "LIVE") : "")
            }
            trailingLabel.frame.origin.x = bounds.width - sideSlotWidth + (isPlaying ? 10 * scale : 0)
        } else {
            trailingLabel.stringValue = HelperUtils.formattedDuration(duration)
            trailingLabel.frame.origin.x = bounds.width - sideSlotWidth
        }
    }

    private func updateLabelStyle() {
        let fontSize = (compactStreamIndicator ? 10 : 11) * scale
        for label in [elapsedLabel, trailingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
            label.textColor = neutral.withAlphaComponent(0.8)
        }
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.backgroundColor = neutral.withAlphaComponent(compactStreamIndicator ? 0.3 : 0.2).cgColor
        fillLayer.backgroundColor = accent.withAlphaComponent(isStream ? 0.45 : 1).cgColor
        bufferingLayer.backgroundColor = accent.withAlphaComponent(0.6).cgColor
        liveDotLayer.backgroundColor = NSColor.systemRed.cgColor
        thumbLayer.backgroundColor = accent.cgColor
        CATransaction.commit()
    }

    private func updateThumbVisibility() {
        thumbLayer.isHidden = isStream || duration <= 0 || (!isDragging && !isHovering)
    }

    private func updateStreamAnimations(bufferWidth: CGFloat) {
        bufferingLayer.isHidden = !isStream || !isBuffering
        liveDotLayer.isHidden = !isStream || (!isPlaying && (!isBuffering || !compactStreamIndicator))
        liveDotLayer.backgroundColor = (isBuffering ? accent : NSColor.systemRed).cgColor
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if bufferingLayer.isHidden || reduceMotion {
            bufferingLayer.removeAnimation(forKey: "sweep")
        } else if bufferingLayer.animation(forKey: "sweep") == nil || animatedTrackFrame != trackFrame {
            let frame = trackFrame
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = frame.minX + bufferWidth / 2
            sweep.toValue = frame.maxX - bufferWidth / 2
            sweep.duration = 1.1
            sweep.autoreverses = true
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bufferingLayer.add(sweep, forKey: "sweep")
        }
        animatedTrackFrame = trackFrame

        if liveDotLayer.isHidden || reduceMotion {
            liveDotLayer.removeAnimation(forKey: "pulse")
            liveDotLayer.opacity = 1
        } else if liveDotLayer.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = isBuffering ? 0.2 : 0.3
            pulse.duration = 0.45
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            liveDotLayer.add(pulse, forKey: "pulse")
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    // MARK: - Accessibility

    override func isAccessibilityElement() -> Bool { !isStream && duration > 0 }
    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityLabel() -> String? { String(localized: "Playback position") }
    override func accessibilityMinValue() -> Any? { 0 }
    override func accessibilityMaxValue() -> Any? { duration }
    override func accessibilityValue() -> Any? { currentTime }

    func accessibilitySetValue(_ value: Any?) {
        guard let value = value as? NSNumber else { return }
        seekFromAccessibility(to: value.doubleValue)
    }

    override func accessibilityPerformIncrement() -> Bool {
        seekFromAccessibility(to: currentTime + 5)
    }

    override func accessibilityPerformDecrement() -> Bool {
        seekFromAccessibility(to: currentTime - 5)
    }

    @discardableResult
    private func seekFromAccessibility(to time: Double) -> Bool {
        guard !isStream, duration > 0 else { return false }
        currentTime = min(duration, max(0, time))
        setProgress(currentTime, animated: false)
        playbackManager?.seekTo(time: currentTime)
        return true
    }
}
