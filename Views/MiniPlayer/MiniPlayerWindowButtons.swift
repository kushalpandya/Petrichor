//
// MiniPlayerWindowButtons
//
// Custom macOS-style close control drawn as a SwiftUI overlay so it floats over
// the artwork (inside the hover region) instead of living in a native title bar.
// The glyph appears while hovered, matching the system behaviour. Only Close is
// shown — a borderless window can't be meaningfully miniaturized/zoomed.
//

import SwiftUI
import AppKit

struct MiniPlayerWindowButtons: View {
    let window: NSWindow?

    @State private var isHoveringCluster = false

    var body: some View {
        HStack(spacing: 8) {
            trafficLight(
                color: Color(red: 1.0, green: 0.37, blue: 0.34),
                glyph: "xmark",
                help: String(localized: "Close")
            ) {
                // The borderless window has no `.closable` style mask, so
                // performClose(nil) would just beep. close() still posts
                // windowWillClose, letting the manager release its reference.
                window?.close()
            }
        }
        .padding(6)
        .miniPlayerControlClusterBackground()
        .onHover { isHoveringCluster = $0 }
    }

    private func trafficLight(
        color: Color,
        glyph: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)

                Image(systemName: glyph)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.black.opacity(0.6))
                    .opacity(isHoveringCluster ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension View {
    /// Blurred, slightly-tinted capsule used behind the mini player's floating
    /// control clusters (window buttons + queue/lyrics toolbar) so their glyphs
    /// stay legible over any artwork.
    func miniPlayerControlClusterBackground() -> some View {
        background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().fill(.black.opacity(0.12)))
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
        )
    }
}
