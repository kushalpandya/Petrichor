import SwiftUI

struct RotatingProgressView: NSViewRepresentable {
    let size: CGFloat
    let lineWidth: CGFloat
    let color: NSColor
    @Binding var isAnimating: Bool
    
    init(size: CGFloat = 16, lineWidth: CGFloat = 2, color: NSColor = .controlAccentColor, isAnimating: Binding<Bool> = .constant(true)) {
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
        self._isAnimating = isAnimating
    }
    
    func makeNSView(context: Context) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = false
        
        let progressLayer = CAShapeLayer()
        progressLayer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = (size - lineWidth) / 2
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360 * 0.7,
            clockwise: true
        )
        
        progressLayer.path = path.cgPath
        progressLayer.strokeColor = color.cgColor
        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.lineWidth = lineWidth
        progressLayer.lineCap = .round
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 1
        
        containerView.layer?.addSublayer(progressLayer)
        context.coordinator.progressLayer = progressLayer
        
        if isAnimating {
            addRotationAnimation(to: progressLayer)
        }
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let progressLayer = context.coordinator.progressLayer else { return }
        
        if isAnimating {
            if progressLayer.animation(forKey: "rotation") == nil {
                addRotationAnimation(to: progressLayer)
            }
        } else {
            progressLayer.removeAnimation(forKey: "rotation")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var progressLayer: CAShapeLayer?
    }
    
    private func addRotationAnimation(to layer: CAShapeLayer) {
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.fromValue = 0
        rotationAnimation.toValue = 2 * Double.pi
        rotationAnimation.duration = 1.5
        rotationAnimation.repeatCount = .infinity
        rotationAnimation.isRemovedOnCompletion = false
        rotationAnimation.fillMode = .forwards
        rotationAnimation.timingFunction = CAMediaTimingFunction(name: .linear)
        
        layer.add(rotationAnimation, forKey: "rotation")
    }
}

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
