import SwiftUI

// MARK: - Activity Animation Size
enum ActivityAnimationSize {
    case small   // For NotificationTray
    case medium  // For LibraryTabView refresh overlay
    case large   // For NoMusicEmptyStateView
    
    var dimensions: CGFloat {
        switch self {
        case .small: return 16
        case .medium: return 64
        case .large: return 88
        }
    }
    
    var lineWidth: CGFloat {
        switch self {
        case .small: return 2
        case .medium: return 4
        case .large: return 5
        }
    }
    
    var iconSize: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 24
        case .large: return 32
        }
    }
    
    var showIcon: Bool {
        switch self {
        case .small: return true
        case .medium, .large: return true
        }
    }
    
    var useSystemIcon: Bool {
        switch self {
        case .small: return true
        case .medium, .large: return false
        }
    }
}

// MARK: - Activity Animation View
struct ActivityAnimation: View {
    let size: ActivityAnimationSize
    @Binding var isAnimating: Bool
    
    init(size: ActivityAnimationSize = .medium, isAnimating: Binding<Bool> = .constant(true)) {
        self.size = size
        self._isAnimating = isAnimating
    }
    
    var body: some View {
        ActivityAnimationRepresentable(size: size, isAnimating: $isAnimating)
            .frame(width: size.dimensions, height: size.dimensions)
    }
}

// MARK: - Internal NSViewRepresentable
private struct ActivityAnimationRepresentable: NSViewRepresentable {
    let size: ActivityAnimationSize
    @Binding var isAnimating: Bool
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: size.dimensions, height: size.dimensions))
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = false
        
        // Create the progress arc layer
        let progressLayer = createProgressLayer()
        containerView.layer?.addSublayer(progressLayer)
        context.coordinator.progressLayer = progressLayer
        
        // Create the icon layer if needed
        if size.showIcon {
            let iconLayer = createIconLayer()
            containerView.layer?.addSublayer(iconLayer)
            context.coordinator.iconLayer = iconLayer
        }
        
        if isAnimating {
            startAnimations(progressLayer: progressLayer, iconLayer: context.coordinator.iconLayer)
        }
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let progressLayer = context.coordinator.progressLayer else { return }
        
        if isAnimating {
            if progressLayer.animation(forKey: "rotation") == nil {
                startAnimations(progressLayer: progressLayer, iconLayer: context.coordinator.iconLayer)
            }
        } else {
            stopAnimations(progressLayer: progressLayer, iconLayer: context.coordinator.iconLayer)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var progressLayer: CAShapeLayer?
        var iconLayer: CALayer?
    }
}

// MARK: - Helper Methods for ActivityAnimationRepresentable

private extension ActivityAnimationRepresentable {
    // MARK: - Layer Creation
    
    func createProgressLayer() -> CAShapeLayer {
        let progressLayer = CAShapeLayer()
        progressLayer.frame = CGRect(x: 0, y: 0, width: size.dimensions, height: size.dimensions)
        
        let center = CGPoint(x: size.dimensions / 2, y: size.dimensions / 2)
        let radius = (size.dimensions - size.lineWidth) / 2
        let path = NSBezierPath()
        
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360 * 0.7,
            clockwise: true
        )
        
        progressLayer.path = path.cgPath
        progressLayer.strokeColor = NSColor.controlAccentColor.cgColor
        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.lineWidth = size.lineWidth
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 1
        
        if size != .small {
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = progressLayer.bounds
            gradientLayer.colors = [
                NSColor.controlAccentColor.cgColor,
                NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor
            ]
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.mask = progressLayer
            
            let containerLayer = CAShapeLayer()
            containerLayer.frame = progressLayer.frame
            containerLayer.addSublayer(gradientLayer)
            return containerLayer
        }
        
        return progressLayer
    }
    
    func createIconLayer() -> CALayer {
        let iconLayer = CALayer()
        let iconSize = size.iconSize
        
        iconLayer.frame = CGRect(
            x: (size.dimensions - iconSize) / 2,
            y: (size.dimensions - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        
        if size.useSystemIcon {
            if let sfImage = NSImage(systemSymbolName: Icons.musicNote, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .bold)
                    .applying(.init(hierarchicalColor: NSColor.controlAccentColor))
                
                if let configuredImage = sfImage.withSymbolConfiguration(config) {
                    iconLayer.contents = configuredImage
                    iconLayer.contentsGravity = .resizeAspect
                    iconLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
                }
            }
        } else {
            if let image = NSImage(named: "custom.music") {
                // Create a tinted version
                let tintedImage = NSImage(size: NSSize(width: iconSize, height: iconSize))
                tintedImage.lockFocus()
                
                // Draw with accent color
                NSGraphicsContext.current?.imageInterpolation = .high
                NSColor.controlAccentColor.set()
                
                // Draw the image
                let rect = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
                image.draw(in: rect)
                
                rect.fill(using: .sourceIn)
                
                tintedImage.unlockFocus()
                
                iconLayer.contents = tintedImage
                iconLayer.contentsGravity = .resizeAspect
                iconLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            }
        }
        
        return iconLayer
    }
    
    // MARK: - Animations
    
    func startAnimations(progressLayer: CAShapeLayer, iconLayer: CALayer?) {
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.fromValue = 0
        rotationAnimation.toValue = 2 * Double.pi
        rotationAnimation.duration = 1.5
        rotationAnimation.repeatCount = .infinity
        rotationAnimation.isRemovedOnCompletion = false
        rotationAnimation.fillMode = .forwards
        rotationAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        progressLayer.add(rotationAnimation, forKey: "rotation")
        
        if let iconLayer = iconLayer, size != .small {
            let scaleAnimation = CAKeyframeAnimation(keyPath: "transform.scale")
            scaleAnimation.values = [1.0, 1.1, 1.0, 0.9, 1.0]
            scaleAnimation.keyTimes = [0, 0.25, 0.5, 0.75, 1.0]
            scaleAnimation.duration = 2.0
            scaleAnimation.repeatCount = .infinity
            scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            opacityAnimation.values = [0.7, 1.0, 0.7]
            opacityAnimation.keyTimes = [0, 0.5, 1.0]
            opacityAnimation.duration = 1.5
            opacityAnimation.repeatCount = .infinity
            opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            iconLayer.add(scaleAnimation, forKey: "scale")
            iconLayer.add(opacityAnimation, forKey: "opacity")
        }
    }
    
    func stopAnimations(progressLayer: CAShapeLayer, iconLayer: CALayer?) {
        progressLayer.removeAnimation(forKey: "rotation")
        
        if let iconLayer = iconLayer {
            iconLayer.removeAnimation(forKey: "scale")
            iconLayer.removeAnimation(forKey: "opacity")
        }
    }
}

// MARK: - NSBezierPath Extension
extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            @unknown default:
                break
            }
        }
        
        return path
    }
}

// MARK: - Preview
#Preview("All Sizes") {
    HStack(spacing: 40) {
        VStack(spacing: 20) {
            Text("Small").font(.caption)
            ActivityAnimation(size: .small)
                .frame(width: 16, height: 16)
        }
        
        VStack(spacing: 20) {
            Text("Medium").font(.caption)
            ActivityAnimation(size: .medium)
                .frame(width: 60, height: 60)
        }
        
        VStack(spacing: 20) {
            Text("Large").font(.caption)
            ActivityAnimation(size: .large)
                .frame(width: 80, height: 80)
        }
    }
    .padding(40)
    .background(Color.gray.opacity(0.1))
}

#Preview("With Toggle") {
    struct PreviewWrapper: View {
        @State private var isAnimating = true
        
        var body: some View {
            VStack(spacing: 30) {
                ActivityAnimation(size: .medium, isAnimating: $isAnimating)
                    .frame(width: 60, height: 60)
                
                Toggle("Animating", isOn: $isAnimating)
                    .toggleStyle(.switch)
            }
            .padding()
        }
    }
    
    return PreviewWrapper()
}
