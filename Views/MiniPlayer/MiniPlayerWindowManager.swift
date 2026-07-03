//
// MiniPlayerWindowManager
//
// Owns the mini player as a custom borderless NSWindow rather than a SwiftUI
// `Window` scene. A SwiftUI-managed window keeps reserving the title-bar height
// (leaving a background strip) and crashes when resized during layout. A plain
// borderless window has no title bar at all, so the artwork is truly edge-to-edge.
// Sizing is driven by MiniPlayerView, which resizes the captured NSWindow via
// `setFrame` + `contentAspectRatio`/min/max (dispatched async, never during layout).
//
// The window uses normal level and opens alongside the main window. Closing it
// only closes this window; with "keep running in menubar on close" enabled the
// app stays alive via the existing AppDelegate logic.
//

import SwiftUI
import AppKit

@MainActor
final class MiniPlayerWindowManager: NSObject {
    static let shared = MiniPlayerWindowManager()

    private static let frameKey = "PetrichorMiniPlayerWindow"

    private var window: NSWindow?

    override private init() {}

    /// Shows the mini player, creating it on first use and focusing the
    /// existing window on subsequent calls.
    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let coordinator = AppCoordinator.shared else {
            Logger.warning("Cannot open mini player: AppCoordinator unavailable")
            return
        }

        let root = MiniPlayerView()
            .environmentObject(coordinator.playbackManager)
            .environmentObject(coordinator.playbackManager.playbackProgressState)
            .environmentObject(coordinator.libraryManager)
            .environmentObject(coordinator.playlistManager)

        // The hosting view fills the window; the window is user-resizable and its
        // size is driven by MiniPlayerView (aspect ratio + min/max).
        let hostingView = NSHostingView(rootView: root)

        let window = MiniPlayerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 280),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Dragging is handled explicitly by MiniPlayerView (on the artwork /
        // panel header) so it doesn't fight queue drag-to-reorder.
        window.isMovableByWindowBackground = false
        window.level = UserDefaults.standard.bool(forKey: "miniPlayerAlwaysOnTop") ? .floating : .normal
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.delegate = self

        // We persist the frame ourselves: NSWindow's autosave remaps onto the main
        // display in multi-monitor setups.
        restoreFrame(into: window)

        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Restores the saved global frame (origin encodes the display) when it's still
    /// on a connected screen; otherwise centers.
    private func restoreFrame(into window: NSWindow) {
        guard let saved = UserDefaults.standard.string(forKey: Self.frameKey) else {
            window.center()
            return
        }
        let frame = NSRectFromString(saved)
        guard frame.width > 0, frame.height > 0,
              NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else {
            window.center()
            return
        }
        window.setFrame(frame, display: false)
    }

    /// Persists the current global frame (origin includes the display).
    private func saveFrame() {
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameKey)
    }
}

extension MiniPlayerWindowManager: NSWindowDelegate {
    // MiniPlayerView's drag/resize fire these. saveFrame no-ops until self.window is
    // set, so the initial restore doesn't overwrite the stored frame.
    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    func windowWillClose(_ notification: Notification) {
        // Intentionally does NOT save playback state here. During app termination
        // this fires after `applicationWillTerminate` has already saved state, so a
        // second save would be redundant. Frame/panel persistence is handled separately.

        // Detach the hosting view so SwiftUI tears the view tree down now (firing
        // onDisappear). Otherwise, with isReleasedWhenClosed = false, a lingering
        // hosting view could leave a fine-progress-sampling consumer registered.
        (notification.object as? NSWindow)?.contentView = nil
        window = nil
    }
}

/// Borderless windows refuse key/main status by default, which would prevent
/// the SwiftUI controls from receiving clicks. Allow both.
final class MiniPlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
