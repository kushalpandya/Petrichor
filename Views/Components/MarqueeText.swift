import SwiftUI
import AppKit

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let containerWidth: CGFloat
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var needsAnimation = false
    
    init(text: String, font: Font = .system(size: 13), color: Color = .primary, containerWidth: CGFloat = .infinity) {
        self.text = text
        self.font = font
        self.color = color
        self.containerWidth = containerWidth
    }
    
    var body: some View {
        GeometryReader { geometry in
            MarqueeTextRepresentable(
                text: text,
                font: font,
                color: color,
                containerWidth: geometry.size.width,
                isActive: scenePhase == .active
            )
        }
        .frame(height: font == .system(size: 12) ? 16 : font == .system(size: 11) ? 14 : 18)
    }
}

// MARK: - NSViewRepresentable for Core Animation

private struct MarqueeTextRepresentable: NSViewRepresentable {
    let text: String
    let font: Font
    let color: Color
    let containerWidth: CGFloat
    let isActive: Bool
    
    func makeNSView(context: Context) -> MarqueeNSView {
        let view = MarqueeNSView()
        view.configure(text: text, font: font, color: color, containerWidth: containerWidth)
        return view
    }
    
    func updateNSView(_ nsView: MarqueeNSView, context: Context) {
        nsView.configure(text: text, font: font, color: color, containerWidth: containerWidth)
        
        if isActive {
            nsView.startAnimationIfNeeded()
        } else {
            nsView.stopAnimation()
        }
    }
}

// MARK: - Custom NSView with CALayer Animation

private class MarqueeNSView: NSView {
    private var textLayer: CATextLayer?
    private var containerLayer: CALayer?
    private var currentText: String = ""
    private var textWidth: CGFloat = 0
    private var containerWidth: CGFloat = 0
    private var isAnimating = false
    private var textColor: Color = .primary
    
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
        
        containerLayer = CALayer()
        containerLayer?.masksToBounds = true
        layer?.addSublayer(containerLayer!)
        
        textLayer = CATextLayer()
        textLayer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer?.alignmentMode = .left
        containerLayer?.addSublayer(textLayer!)
    }
    
    func configure(text: String, font: Font, color: Color, containerWidth: CGFloat) {
        guard let textLayer = textLayer, let containerLayer = containerLayer else { return }
        
        let textChanged = currentText != text
        currentText = text
        self.textColor = color
        self.containerWidth = containerWidth
        
        let nsFont = NSFont.systemFont(ofSize: fontSizeFromFont(font))
        
        let attributes: [NSAttributedString.Key: Any] = [.font: nsFont]
        let textSize = (text as NSString).size(withAttributes: attributes)
        textWidth = textSize.width
        
        containerLayer.frame = CGRect(x: 0, y: 0, width: containerWidth, height: textSize.height)
        
        textLayer.string = text
        textLayer.font = nsFont
        textLayer.fontSize = nsFont.pointSize
        textLayer.foregroundColor = textForegroundColor(for: color)
        textLayer.frame = CGRect(x: 0, y: 0, width: textWidth, height: textSize.height)
        
        if textChanged {
            stopAnimation()
            startAnimationIfNeeded()
        }
    }
    
    func startAnimationIfNeeded() {
        guard textWidth > containerWidth, !isAnimating else { return }
        
        isAnimating = true
        addScrollAnimation()
    }
    
    func stopAnimation() {
        textLayer?.removeAllAnimations()
        textLayer?.position = CGPoint(x: textWidth / 2, y: textLayer?.position.y ?? 0)
        isAnimating = false
    }
    
    private func addScrollAnimation() {
        guard let textLayer = textLayer else { return }
        
        textLayer.removeAllAnimations()
        
        let scrollDistance = textWidth - containerWidth + 20
        let animationDuration: CFTimeInterval = Double(scrollDistance) / 20.0
        
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        
        let startX = textWidth / 2
        let endX = -scrollDistance + textWidth / 2
        
        animation.values = [
            startX,
            startX,
            endX,
            endX,
            startX,
            startX
        ]
        
        animation.keyTimes = [
            0.0,
            0.1,
            0.45,
            0.55,
            0.9,
            1.0
        ]
        
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear)
        ]
        
        animation.duration = (animationDuration * 2) + 2.0
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        
        textLayer.add(animation, forKey: "marqueeAnimation")
    }
    
    private func fontSizeFromFont(_ font: Font) -> CGFloat {
        if font == .system(size: 11) {
            return 11
        } else if font == .system(size: 12) {
            return 12
        } else if font == .system(size: 13) {
            return 13
        } else if font == .system(size: 14) {
            return 14
        } else {
            return 13
        }
    }
    
    private func textForegroundColor(for color: Color) -> CGColor {
        let resolvedColor: NSColor
        switch color {
        case Color.primary:
            resolvedColor = NSColor.labelColor
        case Color.secondary:
            resolvedColor = NSColor.secondaryLabelColor
        case Color.secondary.opacity(0.8):
            resolvedColor = NSColor.secondaryLabelColor.withAlphaComponent(0.8)
        default:
            resolvedColor = NSColor(color)
        }
        return resolvedColor.cgColor
    }
    
    override func layout() {
        super.layout()
        
        if let containerLayer = containerLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            
            containerLayer.frame = bounds
            
            CATransaction.commit()
        }
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        
        textLayer?.foregroundColor = textForegroundColor(for: textColor)
    }
}

// MARK: - Preview

#Preview("Short Text") {
    MarqueeText(
        text: "Short Text",
        font: .system(size: 14),
        color: .primary
    )
    .frame(width: 200)
    .padding()
    .background(Color.gray.opacity(0.1))
}

#Preview("Long Text") {
    MarqueeText(
        text: "This is a very long text that should scroll back and forth continuously",
        font: .system(size: 14),
        color: .primary
    )
    .frame(width: 200)
    .padding()
    .background(Color.gray.opacity(0.1))
}

#Preview("Multiple Marquees") {
    VStack(spacing: 20) {
        MarqueeText(
            text: "Artist Name That Is Really Long And Keeps Going",
            font: .system(size: 13),
            color: .primary
        )
        .frame(width: 150)
        
        MarqueeText(
            text: "Album Title That Goes On Forever And Ever And Ever",
            font: .system(size: 12),
            color: .secondary
        )
        .frame(width: 150)
        
        MarqueeText(
            text: "Short",
            font: .system(size: 11),
            color: .secondary
        )
        .frame(width: 150)
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
