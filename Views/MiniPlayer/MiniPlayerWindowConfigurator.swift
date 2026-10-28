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

    func makeNSView(context: Context) -> WindowReportingView {
        let view = WindowReportingView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: WindowReportingView, context: Context) {
        nsView.onWindow = onWindow
    }
}

/// Reports its window when it joins one, rather than polling once after
/// creation, which misses windows whose first layout is delayed (e.g. opened
/// from the menu bar while another app is in full screen).
private final class WindowReportingView: NSView {
    var onWindow: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // Deferred so the callback's SwiftUI state writes don't land mid-update.
        DispatchQueue.main.async { [weak self] in
            self?.onWindow?(window)
        }
    }
}
