//
// WindowDelegate class
//
// This class handles app window management around its default size and positioning on launch.
//

import AppKit

class WindowDelegate: NSObject, NSWindowDelegate {
    // Flag to ensure we only attempt one corrective reposition. This prevents
    // fighting with tiling/space-managing tools which may
    // legitimately move the window after the initial launch.
    private var didRestoreWindowFrame = false

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Save playback state when window closes
        AppCoordinator.shared?.savePlaybackState()

        // If menubar mode is enabled, hide instead of close
        if UserDefaults.standard.bool(forKey: "closeToMenubar") {
            Logger.info("Menubar mode enabled - hiding window instead of closing")

            // Hide the window
            sender.orderOut(nil)

            // Hide dock icon after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Logger.info("Hiding dock icon...")
                NSApp.setActivationPolicy(.accessory)
            }

            // Prevent actual close
            return false
        }

        // Normal close if menubar mode is disabled
        return true
    }

    // Add this new method to validate window frame
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        // If the window frame looks like a preview frame, return a proper default
        if newFrame.width < 800 || newFrame.height < 600 {
            let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect.zero
            let width: CGFloat = 1200
            let height: CGFloat = 800
            let x = (screenFrame.width - width) / 2 + screenFrame.origin.x
            let y = (screenFrame.height - height) / 2 + screenFrame.origin.y
            return NSRect(x: x, y: y, width: width, height: height)
        }
        return newFrame
    }

   // Add this to prevent saving corrupted frames
   func windowDidMove(_ notification: Notification) {
       guard let window = notification.object as? NSWindow else { return }

       // If we've already handled a potential corrupted frame once, do not
       // interfere with subsequent legitimate moves coming from tiling window
       // managers or the system itself.
       if didRestoreWindowFrame {
           return
       }

       // Check if the window is in a suspicious position (like preview pane)
       let frame = window.frame
       guard let mainScreen = NSScreen.main else { return }
       if frame.width < 800 || frame.height < 600 || frame.origin.x > mainScreen.frame.width - 700 {
           // Don't save this frame
           window.setFrameAutosaveName("")

           // Re-enable autosave after centering
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
               window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 800), display: true)
               window.center()
               window.setFrameAutosaveName("MainWindow")

               // Mark the frame as restored so we don't do this again.
               self.didRestoreWindowFrame = true
           }
       }
   }
}
