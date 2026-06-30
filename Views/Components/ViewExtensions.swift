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

// MARK: - Adaptive Button Styles

extension View {
    @ViewBuilder
    func adaptiveButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                self.foregroundStyle(Color.accentColor)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            } else {
                self.foregroundStyle(.secondary)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                self.buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    func adaptiveCircularButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
        } else {
            self.buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Active Control Indicator

extension View {
    /// Overlays a small dot beneath a transport-control glyph to mark an active
    /// toggle (shuffle/repeat on). An overlay adds no layout space, so the glyph
    /// stays aligned with its neighbors whether or not the dot shows.
    func activeControlIndicator(isActive: Bool, color: Color, scale: CGFloat = 1) -> some View {
        overlay(alignment: .bottom) {
            Circle()
                .fill(color)
                .frame(width: 3.5 * scale, height: 3.5 * scale)
                .offset(y: -3 * scale)
                .opacity(isActive ? 1 : 0)
        }
    }
}

// MARK: - Lossless Label

/// A glyph + "Lossless" label, shared between the track-detail view and the
/// player's format badges. Defaults match the track-detail sizing; the player
/// passes a more compact configuration.
struct LosslessLabel: View {
    var iconSize: CGFloat = 14
    var font: Font = .subheadline
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            Image(Icons.customLossless)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundColor(.secondary)

            Text("Lossless")
                .font(font)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
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
            .overlay(FocusStableMaterial())
        } else {
            GeometryReader { geometry in
                RadialGradient(
                    colors: colors + [.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.width
                )
                .overlay(FocusStableMaterial())
            }
        }
    }
}
