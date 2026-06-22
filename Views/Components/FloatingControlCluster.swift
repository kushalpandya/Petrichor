//
// FloatingControlCluster
//
// Shared building blocks for the floating control clusters used by the mini
// player and immersive mode: a round, artwork-tinted toggle button and the
// blurred capsule backdrop that sits behind a cluster.
//

import SwiftUI

/// A round, hover-scaling toggle button used in the floating control clusters of
/// the mini player and immersive mode. Fills with `activeTint` when active.
struct PanelToolbarButton<Label: View>: View {
    let isActive: Bool
    let isEnabled: Bool
    let activeTint: Color
    let activeHelp: String
    let inactiveHelp: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundColor(isActive ? .white : .secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isActive ? activeTint : Color.clear))
                // Make the whole circle clickable, not just the opaque icon pixels
                // (the inactive background is clear, so it wouldn't hit-test).
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .hoverEffect(scale: isEnabled ? 1.1 : 1.0)
        .help(isActive ? activeHelp : inactiveHelp)
    }
}

extension View {
    /// Backdrop behind a floating control cluster (e.g. the mini player's window
    /// buttons / queue-lyrics toolbar, or the immersive toolbar) so its glyphs stay
    /// legible over any artwork. Uses Liquid Glass on macOS 26+, falling back to a
    /// blurred, slightly-tinted material capsule on earlier releases.
    @ViewBuilder
    func floatingControlClusterBackground() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().fill(.black.opacity(0.12)))
                    .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
            )
        }
    }
}
