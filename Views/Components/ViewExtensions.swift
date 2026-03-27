import SwiftUI

// MARK: - Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Gradient Background

struct GradientBackground: View {
    let colors: [Color]

    var body: some View {
        if #available(macOS 15.0, *), colors.count >= 6 {
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                ],
                colors: [
                    colors[0], colors[1], colors[2],
                    colors[3], colors[4], colors[5],
                    colors[2], colors[0], colors[3]
                ]
            )
            .overlay(.ultraThinMaterial)
        } else {
            GeometryReader { geometry in
                RadialGradient(
                    colors: colors + [.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.width
                )
                .overlay(.ultraThinMaterial)
            }
        }
    }
}
