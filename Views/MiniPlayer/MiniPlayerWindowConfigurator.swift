//
// MiniPlayerWindowConfigurator
//
// The mini player window is created as a borderless NSWindow by
// MiniPlayerWindowManager, so no chrome styling is needed here. This accessor
// simply hands the hosting NSWindow back to SwiftUI so MiniPlayerView can drive
// the floating close button, window level, sizing, and corner rounding.
//

import SwiftUI
import AppKit

extension View {
    func captureMiniPlayerWindow(_ onWindow: @escaping (NSWindow) -> Void) -> some View {
        background(MiniPlayerWindowAccessor(onWindow: onWindow))
    }
}

private struct MiniPlayerWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
