import SwiftUI

// MARK: - Hover Effect Modifier

struct HoverEffect: ViewModifier {
    let scaleAmount: CGFloat?
    let activeColor: Color
    let inactiveColor: Color
    let activeBackgroundColor: Color?
    let cornerRadius: CGFloat
    let padding: CGFloat
    
    @State private var isHovered = false

    init(
        scale: CGFloat? = nil,
        activeColor: Color = .primary,
        inactiveColor: Color = .secondary,
        activeBackgroundColor: Color? = Color(NSColor.controlColor),
        cornerRadius: CGFloat = 4,
        padding: CGFloat = 2
    ) {
        self.scaleAmount = scale
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.activeBackgroundColor = activeBackgroundColor
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    func body(content: Content) -> some View {
        content
            .if(scaleAmount != nil) { view in
                view.scaleEffect(isHovered ? scaleAmount! : 1.0)
            }
            .foregroundColor(isHovered ? activeColor : inactiveColor)
            .if(activeBackgroundColor != nil && padding > 0) { view in
                view.padding(padding)
            }
            .if(activeBackgroundColor != nil) { view in
                view.background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isHovered ? activeBackgroundColor! : Color.clear)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                )
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - View Extension

extension View {
    /// Applies hover effect with color change and optional background
    /// - Parameters:
    ///   - scale: Scale factor when hovered (default: nil - no scaling)
    ///   - activeColor: Foreground color when hovered (default: .primary)
    ///   - inactiveColor: Foreground color when not hovered (default: .secondary)
    ///   - activeBackgroundColor: Background color when hovered (default: controlColor)
    ///   - cornerRadius: Corner radius for background (default: 4)
    ///   - padding: Padding around content when background is shown (default: 2)
    func hoverEffect(
        scale: CGFloat? = nil,
        activeColor: Color = .primary,
        inactiveColor: Color = .secondary,
        activeBackgroundColor: Color? = nil,
        cornerRadius: CGFloat = 4,
        padding: CGFloat = 2
    ) -> some View {
        self.modifier(HoverEffect(
            scale: scale,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            activeBackgroundColor: activeBackgroundColor,
            cornerRadius: cornerRadius,
            padding: padding
        ))
    }
}
