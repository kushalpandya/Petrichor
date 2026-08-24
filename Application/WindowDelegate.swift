//
// WindowDelegate class
//
// This class handles app window management based on user settings
//

import AppKit

@MainActor
class WindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Save playback state when window closes
        AppCoordinator.shared?.savePlaybackState()

        // If menubar mode is enabled, hide instead of close
        if UserDefaults.standard.bool(forKey: "closeToMenubar") {
            Logger.info("Menubar mode enabled - hiding window instead of closing")

            // Hide the window
            sender.orderOut(nil)
            DispatchQueue.main.async {
                WindowManager.shared.playbackWindowVisibilityDidChange()
            }

            // Hide dock icon after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Logger.info("Hiding dock icon...")
                NSApp.setActivationPolicy(.accessory)
            }

            // Prevent actual close
            return false
        }

        // Normal close if menubar mode is disabled
        DispatchQueue.main.async {
            WindowManager.shared.playbackWindowVisibilityDidChange()
        }
        return true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        WindowManager.shared.playbackWindowVisibilityDidChange()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        WindowManager.shared.playbackWindowVisibilityDidChange()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        WindowManager.shared.playbackWindowVisibilityDidChange()
    }
}
