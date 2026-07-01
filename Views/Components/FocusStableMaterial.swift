//
// FocusStableMaterial
//
// A blur/vibrancy layer backed by NSVisualEffectView that stays in its active
// appearance even when its window is not key. SwiftUI's `Material` follows the
// window's key state and dims to a flat, inactive look when the window loses focus,
// which washes out the artwork gradients drawn beneath it. Pinning `state = .active`
// keeps the frosted look constant across focus changes.
//

import SwiftUI
import AppKit

struct FocusStableMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}
